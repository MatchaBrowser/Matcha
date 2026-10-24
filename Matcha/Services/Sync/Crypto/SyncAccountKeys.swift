import CryptoKit
import Foundation

/// Derivation parameters of the master password (`kdf`, `SYNC.md` § 3.1): PBKDF2-SHA256, 16-byte salt.
nonisolated struct SyncKDF: Codable, Equatable, Sendable {
    static let algorithmName = "pbkdf2-sha256"
    /// This Matcha's bounds: a server can neither lower the work to guess the password faster, nor raise it to freeze
    /// this Mac in an endless computation.
    static let minimumIterations = 600_000
    static let maximumIterations = 10_000_000
    static let saltLength = 16

    var algorithm: String
    var iterations: Int
    var salt: Data

    /// New random salt.
    static func random(iterations: Int = minimumIterations) -> SyncKDF {
        SyncKDF(algorithm: algorithmName, iterations: iterations, salt: SyncCrypto.randomBytes(saltLength))
    }

    var isAcceptable: Bool {
        algorithm == Self.algorithmName && (Self.minimumIterations ... Self.maximumIterations).contains(iterations)
            && salt.count == Self.saltLength
    }
}

/// Master password (`SYNC.md` § 3.1): normalized to Unicode NFKD, then encoded as UTF-8; at least 12 characters.
nonisolated enum SyncPassword {
    static let minimumLength = 12

    static func normalized(_ password: String) -> Data {
        Data(password.decomposedStringWithCompatibilityMapping.utf8)
    }

    static func isLongEnough(_ password: String) -> Bool {
        password.count >= minimumLength
    }
}

/// Keys of a sync account (`SYNC.md` § 3.2). Neither the password, nor the master key, nor the recovery key is ever
/// saved; only the account key stays in this Mac's keychain.
nonisolated enum SyncAccountKeys {
    static let accountKeyAAD = Data("matcha.account-key.v1".utf8)

    /// Keys derived from the password: `authKey` proves knowledge of it, `wrapKey` wraps the account key.
    struct PasswordKeys {
        let authKey: SymmetricKey
        let wrapKey: SymmetricKey
    }

    /// Computes the master key (slow: PBKDF2) and its subkeys; rejects a password that is too short or parameters
    /// that are too weak.
    static func passwordKeys(password: String, kdf: SyncKDF) throws -> PasswordKeys {
        guard SyncPassword.isLongEnough(password) else {
            throw SyncCryptoError.passwordTooShort
        }
        guard kdf.isAcceptable else {
            throw SyncCryptoError.weakKDF
        }
        let passwordKey = try SymmetricKey(data: SyncCrypto.pbkdf2(
            password: SyncPassword.normalized(password),
            salt: kdf.salt,
            iterations: kdf.iterations,
        ))
        return PasswordKeys(
            authKey: SyncCrypto.subkey(of: passwordKey, info: "matcha.auth.v1"),
            wrapKey: SyncCrypto.subkey(of: passwordKey, info: "matcha.wrap.v1"),
        )
    }

    /// Keys derived from the recovery key.
    static func recoveryKeys(_ recoveryKey: SyncRecoveryKey) -> PasswordKeys {
        let key = SymmetricKey(data: recoveryKey.bytes)
        return PasswordKeys(
            authKey: SyncCrypto.subkey(of: key, info: "matcha.recovery-auth.v1"),
            wrapKey: SyncCrypto.subkey(of: key, info: "matcha.recovery-wrap.v1"),
        )
    }

    /// Key for the records.
    static func dataKey(accountKey: SymmetricKey) -> SymmetricKey {
        SyncCrypto.subkey(of: accountKey, info: "matcha.data.v1")
    }

    /// Key of the identifiers derived from a name (`SyncIdentifiers`).
    static func idKey(accountKey: SymmetricKey) -> SymmetricKey {
        SyncCrypto.subkey(of: accountKey, info: "matcha.id.v1")
    }

    static func wrap(_ accountKey: SymmetricKey, with wrapKey: SymmetricKey) throws -> Data {
        try SyncCrypto.seal(accountKey.withUnsafeBytes { Data($0) }, key: wrapKey, aad: accountKeyAAD)
    }

    /// Unwrapped account key; a failure means a tampered envelope or a wrong key.
    static func unwrap(_ wrapped: Data, with wrapKey: SymmetricKey) throws -> SymmetricKey {
        let bytes = try SyncCrypto.open(wrapped, key: wrapKey, aad: accountKeyAAD)
        guard bytes.count == 32 else {
            throw SyncCryptoError.unreadable
        }
        return SymmetricKey(data: bytes)
    }

    /// Data for creating an account (`SYNC.md` § 3.3): salt, account key and recovery key drawn at random.
    struct Creation {
        let kdf: SyncKDF
        let authKey: Data
        let wrappedAccountKey: Data
        let recoveryAuthKey: Data
        let recoveryWrappedAccountKey: Data
        let accountKey: SymmetricKey
        let recoveryKey: SyncRecoveryKey
    }

    static func creation(password: String, iterations: Int = SyncKDF.minimumIterations) throws -> Creation {
        let kdf = SyncKDF.random(iterations: iterations)
        let keys = try passwordKeys(password: password, kdf: kdf)
        let accountKey = SymmetricKey(size: .bits256)
        let recoveryKey = SyncRecoveryKey.random()
        let recovery = recoveryKeys(recoveryKey)
        return try Creation(
            kdf: kdf,
            authKey: keys.authKey.withUnsafeBytes { Data($0) },
            wrappedAccountKey: wrap(accountKey, with: keys.wrapKey),
            recoveryAuthKey: recovery.authKey.withUnsafeBytes { Data($0) },
            recoveryWrappedAccountKey: wrap(accountKey, with: recovery.wrapKey),
            accountKey: accountKey,
            recoveryKey: recoveryKey,
        )
    }
}
