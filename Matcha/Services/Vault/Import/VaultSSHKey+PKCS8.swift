import CryptoKit
import Foundation

/// PKCS#8 (RFC 5208, RFC 8410): the `PrivateKeyInfo` in DER of CXF's `ssh-key` and of 1Password, unencrypted.
nonisolated extension VaultSSHKey {
    private static let ed25519OID: [UInt8] = [0x2B, 0x65, 0x70]
    private static let ellipticCurveOID: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    private static let p256OID: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
    private static let p384OID: [UInt8] = [0x2B, 0x81, 0x04, 0x00, 0x22]
    private static let rsaOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    /// The key of a `PrivateKeyInfo` (version 1 or 2); nil for another algorithm or curve, or a malformed one.
    init?(pkcs8 der: Data, comment: String) {
        var outer = DERReader(bytes: [UInt8](der))
        guard var info = outer.element(tag: 0x30), let version = info.element(tag: 0x02)?.bytes, version == [0] || version == [1],
              var algorithm = info.element(tag: 0x30), let oid = algorithm.element(tag: 0x06)?.bytes,
              let privateKey = info.element(tag: 0x04)?.bytes
        else {
            return nil
        }
        var inner = DERReader(bytes: privateKey)
        let material: Material
        switch oid {
        case Self.ed25519OID:
            guard let seed = inner.element(tag: 0x04)?.bytes, seed.count == 32 else {
                return nil
            }
            material = .ed25519(seed: seed)
        case Self.ellipticCurveOID:
            // ECPrivateKey (RFC 5915): version 1, then the scalar.
            guard let curve = algorithm.element(tag: 0x06)?.bytes, var key = inner.element(tag: 0x30), key.element(tag: 0x02)?.bytes == [1],
                  let scalar = key.element(tag: 0x04)?.bytes, let ecdsa = Self.ecdsa(curve: curve, scalar: scalar)
            else {
                return nil
            }
            material = ecdsa
        case Self.rsaOID:
            guard let rsa = Self.rsa(pkcs1: &inner) else {
                return nil
            }
            material = .rsa(rsa)
        default:
            return nil
        }
        self.init(material: material, comment: comment)
        guard publicBlob != nil else {
            return nil
        }
    }

    private static func ecdsa(curve: [UInt8], scalar: [UInt8]) -> Material? {
        switch curve {
        case p256OID where scalar.count == 32: .p256(scalar)
        case p384OID where scalar.count == 48: .p384(scalar)
        default: nil
        }
    }

    /// `RSAPrivateKey` (PKCS#1): version, n, e, d, p, q, d mod (p − 1), d mod (q − 1), q⁻¹ mod p.
    private static func rsa(pkcs1 reader: inout DERReader) -> RSA? {
        guard var key = reader.element(tag: 0x30), key.element(tag: 0x02)?.bytes == [0] else {
            return nil
        }
        let values = (0 ..< 8).compactMap { _ in key.element(tag: 0x02)?.bytes }.map(VaultSSHEncoding.stripped)
        guard values.count == 8, values.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return RSA(
            modulus: values[0],
            publicExponent: values[1],
            privateExponent: values[2],
            coefficient: values[7],
            prime1: values[3],
            prime2: values[4],
        )
    }

    /// The key as a `PrivateKeyInfo` in DER (version 1); nil if it is not a valid key.
    var pkcs8: Data? {
        let encoding = VaultSSHEncoding.self
        let version = encoding.derInteger([])
        switch material {
        case let .ed25519(seed):
            let algorithm = encoding.der(0x30, encoding.der(0x06, Self.ed25519OID))
            return Data(encoding.der(0x30, version + algorithm + encoding.der(0x04, encoding.der(0x04, seed))))
        case let .p256(scalar):
            return (try? P256.Signing.PrivateKey(rawRepresentation: scalar))?.derRepresentation
        case let .p384(scalar):
            return (try? P384.Signing.PrivateKey(rawRepresentation: scalar))?.derRepresentation
        case let .rsa(rsa):
            guard let prime1MinusOne = encoding.minusOne(rsa.prime1), let prime2MinusOne = encoding.minusOne(rsa.prime2),
                  let exponent1 = encoding.remainder(rsa.privateExponent, modulo: prime1MinusOne),
                  let exponent2 = encoding.remainder(rsa.privateExponent, modulo: prime2MinusOne)
            else {
                return nil
            }
            let integers = [
                [], rsa.modulus, rsa.publicExponent, rsa.privateExponent, rsa.prime1, rsa.prime2, exponent1, exponent2, rsa.coefficient,
            ]
            let key = encoding.der(0x30, integers.flatMap(encoding.derInteger))
            let algorithm = encoding.der(0x30, encoding.der(0x06, Self.rsaOID) + [0x05, 0x00])
            return Data(encoding.der(0x30, version + algorithm + encoding.der(0x04, key)))
        }
    }
}
