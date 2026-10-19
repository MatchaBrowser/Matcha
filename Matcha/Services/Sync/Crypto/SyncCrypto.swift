import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Encryption for sync through a server (task 7.5, `SYNC.md` § 3): master password derivation
/// (PBKDF2-HMAC-SHA256), subkeys (HKDF-SHA256, empty salt), AES-256-GCM (random 12-byte nonce), ISO/IEC 7816-4
/// padding that hides the exact size. Content that was modified, moved or is in another format is rejected. Pure type.
nonisolated enum SyncCrypto {
    /// Version byte at the start of an encrypted content or package.
    static let formatVersion: UInt8 = 1
    /// A record's content is padded to a multiple of 256 bytes, an extension package to a multiple of 64 KiB.
    static let recordPadding = 256
    static let blobPadding = 65536

    // MARK: Keys

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

    /// 32-byte subkey: HKDF-SHA256 of `key`, empty salt, `info` in UTF-8.
    static func subkey(of key: SymmetricKey, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: Data(), info: Data(info.utf8), outputByteCount: 32)
    }

    /// Bytes from the system's generator.
    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            buffer.baseAddress.map { SecRandomCopyBytes(kSecRandomDefault, count, $0) } ?? errSecAllocate
        }
        precondition(status == errSecSuccess, "Générateur aléatoire indisponible")
        return data
    }

    // MARK: Encryption

    /// `nonce ‖ ciphertext ‖ tag`; `nonce` is only passed by tests (fixed vectors).
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

    /// Padding: `0x80`, then `0x00` bytes up to a multiple of `block`.
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

    // MARK: Records and packages

    /// Encrypted content of a record (`SYNC.md` § 3.5), in base 64: bound to its identifier and to `keyVersion`.
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

    /// Extension package encrypted with its own key, bound to its identifier (`SYNC.md` § 3.5).
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

    /// What follows the version byte, if it is known.
    private static func versioned(_ data: Data) throws -> Data {
        guard data.first == formatVersion else {
            throw SyncCryptoError.unreadable
        }
        return data.dropFirst()
    }
}

nonisolated enum SyncCryptoError: Error, Equatable {
    /// Fewer than `SyncPassword.minimumLength` characters.
    case passwordTooShort
    /// Derivation parameters weaker than this Matcha's minimum.
    case weakKDF
    case keyDerivationFailed
    /// Content tampered with, moved, from another key or in an unknown format.
    case unreadable
    case invalidRecoveryKey
}
