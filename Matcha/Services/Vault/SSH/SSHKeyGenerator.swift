import CryptoKit
import Foundation
import Security

/// Creation of the vault's SSH keys (`VAULT.md` § 9.4): Ed25519 and ECDSA through CryptoKit, RSA through Security, of
/// 3 072 or 4 096 bits. RSA takes a moment (up to a few seconds for 4 096 bits): to be called away from the main
/// actor. Pure type.
nonisolated enum SSHKeyGenerator {
    /// The RSA sizes offered.
    static let rsaSizes = [3072, 4096]

    /// A new key of type `type`; `rsaBits` is only read for RSA.
    static func generate(_ type: SSHKeyType, rsaBits: Int = 4096, comment: String) throws(SSHKeyError) -> SSHKey {
        let key: SSHPrivateKey = switch type {
        case .ed25519: .ed25519(Curve25519.Signing.PrivateKey())
        case .ecdsaP256: .ecdsaP256(P256.Signing.PrivateKey())
        case .ecdsaP384: .ecdsaP384(P384.Signing.PrivateKey())
        case .rsa: try .rsa(rsaKey(bits: rsaBits))
        }
        return SSHKey(key, comment: comment)
    }

    /// An RSA key from `SecKeyCreateRandomKey`, kept in memory only, whose PKCS#1 export gives the numbers.
    private static func rsaKey(bits: Int) throws(SSHKeyError) -> SSHRSAKey {
        guard rsaSizes.contains(bits) else {
            throw .invalidRSASize
        }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits]
        var error: Unmanaged<CFError>?
        defer { error?.release() }
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let exported = SecKeyCopyExternalRepresentation(key, &error) as Data?,
              let rsa = try? SSHRSAKey(pkcs1: Array(exported))
        else {
            throw .generationFailed
        }
        return rsa
    }
}
