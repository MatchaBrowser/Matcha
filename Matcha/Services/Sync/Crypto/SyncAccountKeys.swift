import CryptoKit
import Foundation

/// Paramètres de dérivation du mot de passe maître (`kdf`, `SYNC.md` § 3.1) : PBKDF2-SHA256, sel de 16 octets.
nonisolated struct SyncKDF: Codable, Equatable, Sendable {
    static let algorithmName = "pbkdf2-sha256"
    /// Minimum de ce Matcha : un serveur ne peut pas l'abaisser pour deviner plus vite le mot de passe.
    static let minimumIterations = 600_000

    var algorithm: String
    var iterations: Int
    var salt: Data

    /// Nouveau sel aléatoire.
    static func random(iterations: Int = minimumIterations) -> SyncKDF {
        SyncKDF(algorithm: algorithmName, iterations: iterations, salt: SyncCrypto.randomBytes(16))
    }

    var isAcceptable: Bool {
        algorithm == Self.algorithmName && iterations >= Self.minimumIterations && salt.count >= 16
    }
}

/// Mot de passe maître (`SYNC.md` § 3.1) : normalisé en Unicode NFKD, puis encodé en UTF-8 ; 12 caractères au moins.
nonisolated enum SyncPassword {
    static let minimumLength = 12

    static func normalized(_ password: String) -> Data {
        Data(password.decomposedStringWithCompatibilityMapping.utf8)
    }

    static func isLongEnough(_ password: String) -> Bool {
        password.count >= minimumLength
    }
}

/// Clés d'un compte de synchro (`SYNC.md` § 3.2). Ni le mot de passe, ni la clé maître, ni la clé de secours ne sont
/// jamais enregistrés ; seule la clé de compte reste dans le trousseau de ce Mac.
nonisolated enum SyncAccountKeys {
    static let accountKeyAAD = Data("matcha.account-key.v1".utf8)

    /// Clés tirées du mot de passe : `authKey` prouve qu'on le connaît, `wrapKey` enveloppe la clé de compte.
    struct PasswordKeys {
        let authKey: SymmetricKey
        let wrapKey: SymmetricKey
    }

    /// Calcule la clé maître (lent : PBKDF2) et ses sous-clés ; refuse un mot de passe trop court ou des paramètres
    /// trop faibles.
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

    /// Clés tirées de la clé de secours.
    static func recoveryKeys(_ recoveryKey: SyncRecoveryKey) -> PasswordKeys {
        let key = SymmetricKey(data: recoveryKey.bytes)
        return PasswordKeys(
            authKey: SyncCrypto.subkey(of: key, info: "matcha.recovery-auth.v1"),
            wrapKey: SyncCrypto.subkey(of: key, info: "matcha.recovery-wrap.v1"),
        )
    }

    /// Clé des enregistrements.
    static func dataKey(accountKey: SymmetricKey) -> SymmetricKey {
        SyncCrypto.subkey(of: accountKey, info: "matcha.data.v1")
    }

    static func wrap(_ accountKey: SymmetricKey, with wrapKey: SymmetricKey) throws -> Data {
        try SyncCrypto.seal(accountKey.withUnsafeBytes { Data($0) }, key: wrapKey, aad: accountKeyAAD)
    }

    /// Clé de compte ouverte ; un échec veut dire une enveloppe altérée ou une mauvaise clé.
    static func unwrap(_ wrapped: Data, with wrapKey: SymmetricKey) throws -> SymmetricKey {
        let bytes = try SyncCrypto.open(wrapped, key: wrapKey, aad: accountKeyAAD)
        guard bytes.count == 32 else {
            throw SyncCryptoError.unreadable
        }
        return SymmetricKey(data: bytes)
    }

    /// Données de la création d'un compte (`SYNC.md` § 3.3) : sel, clé de compte et clé de secours tirés au hasard.
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
