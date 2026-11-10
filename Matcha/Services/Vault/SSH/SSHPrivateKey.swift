import CryptoKit
import Foundation

/// A private key once read or generated, whatever its format: CryptoKit's keys for Ed25519 and ECDSA, whose creation
/// checks the scalar, and `SSHRSAKey`. Knows its SSH encodings: the public key (what `authorized_keys` and the
/// fingerprint use) and the type's part of OpenSSH's private section (`PROTOCOL.key`). Pure type.
nonisolated enum SSHPrivateKey {
    case ed25519(Curve25519.Signing.PrivateKey)
    case ecdsaP256(P256.Signing.PrivateKey)
    case ecdsaP384(P384.Signing.PrivateKey)
    case rsa(SSHRSAKey)

    private static let ed25519KeySize = 32

    var keyType: SSHKeyType {
        switch self {
        case .ed25519: .ed25519
        case .ecdsaP256: .ecdsaP256
        case .ecdsaP384: .ecdsaP384
        case .rsa: .rsa
        }
    }

    /// The size of an RSA modulus; nil for the other types.
    var bits: Int? {
        if case let .rsa(key) = self {
            return key.bits
        }
        return nil
    }

    /// The public key in SSH's encoding: RFC 8709 § 4 (Ed25519), RFC 5656 § 3.1 (ECDSA: type, curve, uncompressed
    /// point), RFC 4253 § 6.6 (RSA).
    var publicBlob: [UInt8] {
        var writer = SSHWireWriter()
        switch self {
        case let .ed25519(key):
            writer.write(string: keyType.rawValue)
            writer.write(string: Array(key.publicKey.rawRepresentation))
        case .ecdsaP256, .ecdsaP384:
            writer.write(string: keyType.rawValue)
            writer.write(string: keyType.curveName ?? "")
            writer.write(string: ecdsaPoint ?? [])
        case let .rsa(key):
            return key.publicBlob
        }
        return writer.bytes
    }

    /// An ECDSA key's public point, uncompressed (`04 ‖ x ‖ y`).
    private var ecdsaPoint: [UInt8]? {
        switch self {
        case let .ecdsaP256(key): Array(key.publicKey.x963Representation)
        case let .ecdsaP384(key): Array(key.publicKey.x963Representation)
        case .ed25519, .rsa: nil
        }
    }

    /// The type's part of OpenSSH's private section (`sshkey_private_serialize`), type name included: for Ed25519 the
    /// public key and the 64-byte secret (seed ‖ public key), for ECDSA the curve, the point and the scalar, for RSA
    /// `n, e, d, iqmp, p, q`.
    func writePrivate(to writer: inout SSHWireWriter) {
        writer.write(string: keyType.rawValue)
        switch self {
        case let .ed25519(key):
            let publicKey = Array(key.publicKey.rawRepresentation)
            writer.write(string: publicKey)
            writer.write(string: Array(key.rawRepresentation) + publicKey)
        case let .ecdsaP256(key):
            writeECDSA(scalar: Array(key.rawRepresentation), to: &writer)
        case let .ecdsaP384(key):
            writeECDSA(scalar: Array(key.rawRepresentation), to: &writer)
        case let .rsa(key):
            key.writePrivate(to: &writer)
        }
    }

    private func writeECDSA(scalar: [UInt8], to writer: inout SSHWireWriter) {
        writer.write(string: keyType.curveName ?? "")
        writer.write(string: ecdsaPoint ?? [])
        writer.write(mpint: scalar)
    }

    /// Reads the type's part of OpenSSH's private section, written by `writePrivate(to:)`; the public key it holds must
    /// be that of the private key.
    static func read(from reader: inout SSHWireReader) throws(SSHKeyError) -> SSHPrivateKey {
        let name = try reader.readName()
        guard let type = SSHKeyType(rawValue: name) else {
            throw .unsupported(.keyType(name))
        }
        switch type {
        case .ed25519:
            let publicKey = try reader.readString()
            let secret = try reader.readString()
            guard secret.count == 2 * ed25519KeySize, Array(secret[ed25519KeySize...]) == publicKey else {
                throw .malformed
            }
            return try ed25519Key(seed: Array(secret[..<ed25519KeySize]), publicKey: publicKey)
        case .ecdsaP256, .ecdsaP384:
            guard try reader.readName() == type.curveName else {
                throw .malformed
            }
            let point = try reader.readString()
            return try ecdsaKey(type, scalar: reader.readMPInt(), publicPoint: point)
        case .rsa:
            return try .rsa(SSHRSAKey(reading: &reader))
        }
    }

    /// Ed25519 key from its 32-byte seed; `publicKey`, when given, must be the one derived from it.
    static func ed25519Key(seed: [UInt8], publicKey: [UInt8]?) throws(SSHKeyError) -> SSHPrivateKey {
        guard seed.count == ed25519KeySize, let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed),
              publicKey.map({ $0 == Array(key.publicKey.rawRepresentation) }) ?? true
        else {
            throw .malformed
        }
        return .ed25519(key)
    }

    /// ECDSA key from its scalar, big-endian, leading zeros optional; `publicPoint`, when given, must be the
    /// uncompressed point derived from it.
    static func ecdsaKey(_ type: SSHKeyType, scalar: [UInt8], publicPoint: [UInt8]?) throws(SSHKeyError) -> SSHPrivateKey {
        let magnitude = scalar.drop { $0 == 0 }
        guard let size = type.scalarSize, magnitude.count <= size else {
            throw .malformed
        }
        let raw = [UInt8](repeating: 0, count: size - magnitude.count) + magnitude
        let key: SSHPrivateKey? = switch type {
        case .ecdsaP256: (try? P256.Signing.PrivateKey(rawRepresentation: raw)).map { .ecdsaP256($0) }
        case .ecdsaP384: (try? P384.Signing.PrivateKey(rawRepresentation: raw)).map { .ecdsaP384($0) }
        case .ed25519, .rsa: nil
        }
        guard let key, publicPoint.map({ $0 == key.ecdsaPoint }) ?? true else {
            throw .malformed
        }
        return key
    }
}
