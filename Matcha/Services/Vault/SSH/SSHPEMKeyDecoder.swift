import Foundation

/// Decoding of the unencrypted private keys of PEM files: PKCS#8 (`BEGIN PRIVATE KEY`, RFC 5208 and 5958) for
/// Ed25519, ECDSA and RSA, and SEC1 (`BEGIN EC PRIVATE KEY`, RFC 5915); PKCS#1 is `SSHRSAKey(pkcs1:)`. Curves are named
/// or, as `ssh-keygen` writes them, given by explicit parameters, recognized by their field's prime. A public key in
/// the file must match the private one. Pure type.
nonisolated enum SSHPEMKeyDecoder {
    private static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    private static let ecPublicKey: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    private static let ed25519: [UInt8] = [0x2B, 0x65, 0x70]
    private static let primeField: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x01, 0x01]
    private static let namedCurves: [[UInt8]: SSHKeyType] = [
        [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]: .ecdsaP256, // prime256v1
        [0x2B, 0x81, 0x04, 0x00, 0x22]: .ecdsaP384, // secp384r1
    ]
    /// The primes of the fields of P-256 and P-384 (FIPS 186-4, appendix D.1.2).
    private static let fieldPrimes: [[UInt8]: SSHKeyType] = [
        bytes("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"): .ecdsaP256,
        bytes("fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff"): .ecdsaP384,
    ]
    /// Context-specific tags: SEC1's parameters and public key, PKCS#8's attributes and public key (implicit).
    private static let explicit0: UInt8 = 0xA0
    private static let explicit1: UInt8 = 0xA1
    private static let implicit1: UInt8 = 0x81

    /// A PKCS#8 `PrivateKeyInfo` or `OneAsymmetricKey`.
    static func pkcs8(_ der: [UInt8]) throws(SSHKeyError) -> SSHPrivateKey {
        var outer = SSHDERReader(der)
        var info = try outer.readNested()
        guard outer.isAtEnd, try info.readSmallInteger() <= 1 else {
            throw .malformed
        }
        var algorithm = try info.readNested()
        let identifier = try algorithm.read(SSHDERReader.objectIdentifier)
        let privateKey = try info.read(SSHDERReader.octetString)
        _ = try info.readIfPresent(explicit0)
        let publicKey = try info.readIfPresent(implicit1)
        guard info.isAtEnd, publicKey.map({ $0.first == 0 }) ?? true else {
            throw .malformed
        }
        switch identifier {
        case rsaEncryption:
            _ = try algorithm.readIfPresent(SSHDERReader.null)
            guard algorithm.isAtEnd else {
                throw .malformed
            }
            return try .rsa(SSHRSAKey(pkcs1: privateKey))
        case ecPublicKey:
            let curve = try curve(in: &algorithm)
            guard algorithm.isAtEnd else {
                throw .malformed
            }
            return try sec1(privateKey, curve: curve)
        case ed25519:
            var seed = SSHDERReader(privateKey)
            let bytes = try seed.read(SSHDERReader.octetString)
            guard algorithm.isAtEnd, seed.isAtEnd else {
                throw .malformed
            }
            return try SSHPrivateKey.ed25519Key(seed: bytes, publicKey: publicKey.map { Array($0.dropFirst()) })
        default:
            throw .unsupported(.keyType(SSHDERReader.dotted(identifier)))
        }
    }

    /// A SEC1 `ECPrivateKey`; `curve` is the one PKCS#8's algorithm gives, which the key's parameters, if any, must
    /// repeat.
    static func sec1(_ der: [UInt8], curve: SSHKeyType?) throws(SSHKeyError) -> SSHPrivateKey {
        var outer = SSHDERReader(der)
        var key = try outer.readNested()
        guard outer.isAtEnd, try key.readSmallInteger() == 1 else {
            throw .malformed
        }
        let scalar = try key.read(SSHDERReader.octetString)
        var keyCurve = curve
        if let parameters = try key.readIfPresent(explicit0) {
            var reader = SSHDERReader(parameters)
            let named = try self.curve(in: &reader)
            guard reader.isAtEnd, curve.map({ $0 == named }) ?? true else {
                throw .malformed
            }
            keyCurve = named
        }
        var point: [UInt8]?
        if let publicKey = try key.readIfPresent(explicit1) {
            var reader = SSHDERReader(publicKey)
            point = try reader.readBitString()
            guard reader.isAtEnd else {
                throw .malformed
            }
        }
        guard key.isAtEnd, let keyCurve else {
            throw .malformed
        }
        return try SSHPrivateKey.ecdsaKey(keyCurve, scalar: scalar, publicPoint: point)
    }

    /// The curve of `ECParameters`: a named curve, or explicit parameters (`SpecifiedECDomain`) whose field is that
    /// of P-256 or P-384.
    private static func curve(in reader: inout SSHDERReader) throws(SSHKeyError) -> SSHKeyType {
        if let name = try reader.readIfPresent(SSHDERReader.objectIdentifier) {
            guard let curve = namedCurves[name] else {
                throw .unsupported(.keyType(SSHDERReader.dotted(name)))
            }
            return curve
        }
        var domain = try reader.readNested()
        _ = try domain.readSmallInteger()
        var field = try domain.readNested()
        guard try field.read(SSHDERReader.objectIdentifier) == primeField, let curve = try fieldPrimes[field.readInteger()] else {
            throw .unsupported(.keyType(SSHDERReader.dotted(ecPublicKey)))
        }
        return curve
    }

    /// Bytes of a hexadecimal constant.
    private static func bytes(_ hex: String) -> [UInt8] {
        let digits = Array(hex)
        return stride(from: 0, to: digits.count - 1, by: 2).compactMap { index in
            UInt8(String(digits[index ... index + 1]), radix: 16)
        }
    }
}
