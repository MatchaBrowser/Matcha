import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Chiffrement de la synchro par un serveur (tâche 7.5, `SYNC.md` § 3) : dérivation du mot de passe maître
/// (PBKDF2-HMAC-SHA256), sous-clés (HKDF-SHA256, sel vide), AES-256-GCM (nonce aléatoire de 12 octets), complément
/// ISO/IEC 7816-4 qui cache la taille exacte. Un contenu modifié, déplacé ou d'un autre format est refusé. Type pur.
nonisolated enum SyncCrypto {
    /// Octet de version en tête d'un contenu ou d'un paquet chiffré.
    static let formatVersion: UInt8 = 1
    /// Un contenu d'enregistrement est complété jusqu'à un multiple de 256 octets, un paquet d'extension de 64 Kio.
    static let recordPadding = 256
    static let blobPadding = 65536

    // MARK: Clés

    /// PBKDF2-HMAC-SHA256 (`CCKeyDerivationPBKDF`).
    static func pbkdf2(password: Data, salt: Data, iterations: Int, length: Int = 32) throws -> Data {
        var derived = Data(count: length)
        let status = derived.withUnsafeMutableBytes { output in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(clamping: iterations),
                        output.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        length,
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw SyncCryptoError.keyDerivationFailed
        }
        return derived
    }

    /// Sous-clé de 32 octets : HKDF-SHA256 de `key`, sel vide, `info` en UTF-8.
    static func subkey(of key: SymmetricKey, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: Data(), info: Data(info.utf8), outputByteCount: 32)
    }

    /// Octets du générateur du système.
    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            buffer.baseAddress.map { SecRandomCopyBytes(kSecRandomDefault, count, $0) } ?? errSecAllocate
        }
        precondition(status == errSecSuccess, "Générateur aléatoire indisponible")
        return data
    }

    // MARK: Chiffrement

    /// `nonce ‖ chiffré ‖ étiquette` ; `nonce` n'est donné que par les tests (vecteurs fixes).
    static func seal(_ plaintext: Data, key: SymmetricKey, aad: Data, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key, nonce: nonce ?? AES.GCM.Nonce(), authenticating: aad).combined else {
            throw SyncCryptoError.unreadable
        }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: aad)
        } catch {
            throw SyncCryptoError.unreadable
        }
    }

    /// Complément : `0x80`, puis des `0x00` jusqu'à un multiple de `block`.
    static func pad(_ data: Data, toMultipleOf block: Int) -> Data {
        var padded = data
        padded.append(0x80)
        let remainder = padded.count % block
        if remainder != 0 {
            padded.append(Data(count: block - remainder))
        }
        return padded
    }

    static func unpad(_ data: Data) throws -> Data {
        guard let marker = data.lastIndex(where: { $0 != 0 }), data[marker] == 0x80 else {
            throw SyncCryptoError.unreadable
        }
        return data[data.startIndex ..< marker]
    }

    // MARK: Enregistrements et paquets

    /// Contenu d'un enregistrement chiffré (`SYNC.md` § 3.5), en base 64 : lié à son identifiant et à `keyVersion`.
    static func encryptRecord(
        _ content: Data,
        id: UUID,
        keyVersion: Int,
        dataKey: SymmetricKey,
        nonce: AES.GCM.Nonce? = nil,
    ) throws -> String {
        let sealed = try seal(
            pad(content, toMultipleOf: recordPadding),
            key: dataKey,
            aad: recordAAD(id: id, keyVersion: keyVersion),
            nonce: nonce,
        )
        return (Data([formatVersion]) + sealed).base64EncodedString()
    }

    static func decryptRecord(_ payload: String, id: UUID, keyVersion: Int, dataKey: SymmetricKey) throws -> Data {
        guard let data = Data(base64Encoded: payload) else {
            throw SyncCryptoError.unreadable
        }
        return try unpad(open(versioned(data), key: dataKey, aad: recordAAD(id: id, keyVersion: keyVersion)))
    }

    /// Paquet d'extension chiffré par sa propre clé, lié à son identifiant (`SYNC.md` § 3.5).
    static func encryptBlob(_ package: Data, id: UUID, key: SymmetricKey, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        try Data([formatVersion]) + seal(pad(package, toMultipleOf: blobPadding), key: key, aad: blobAAD(id: id), nonce: nonce)
    }

    static func decryptBlob(_ data: Data, id: UUID, key: SymmetricKey) throws -> Data {
        try unpad(open(versioned(data), key: key, aad: blobAAD(id: id)))
    }

    static func recordAAD(id: UUID, keyVersion: Int) -> Data {
        Data("matcha.record.v1|\(id.uuidString.lowercased())|\(keyVersion)".utf8)
    }

    static func blobAAD(id: UUID) -> Data {
        Data("matcha.blob.v1|\(id.uuidString.lowercased())".utf8)
    }

    /// Ce qui suit l'octet de version, s'il est connu.
    private static func versioned(_ data: Data) throws -> Data {
        guard data.first == formatVersion else {
            throw SyncCryptoError.unreadable
        }
        return data.dropFirst()
    }
}

nonisolated enum SyncCryptoError: Error, Equatable {
    /// Moins de `SyncPassword.minimumLength` caractères.
    case passwordTooShort
    /// Paramètres de dérivation plus faibles que le minimum de ce Matcha.
    case weakKDF
    case keyDerivationFailed
    /// Contenu altéré, déplacé, d'une autre clé ou d'un format inconnu.
    case unreadable
    case invalidRecoveryKey
}
