import CryptoKit
import Foundation

/// The keys of the account flows (`SYNC.md` § 3): the current password's, derived off the main thread, and the
/// envelopes of a recovery key.
extension SyncService {
    /// `authKey` of the current password and of the kept Secret Key, which the sensitive operations require
    /// (`SYNC.md` § 4.1).
    func currentAuthKey(password: String, client: SyncAPIClient) async throws -> Data {
        try await Self.bytes(currentKeys(password: password, client: client).authKey)
    }

    /// Keys of the current password and of the kept Secret Key: `authKey`, and `wrapKey`, which opens the vault's
    /// envelope.
    func currentKeys(password: String, client: SyncAPIClient) async throws -> SyncAccountKeys.PasswordKeys {
        guard let email = configuration.email else {
            throw SyncClientError.signedOut
        }
        let secretKey = try storedSecretKey()
        let kdf = try await client.prelogin(email: email)
        return try await Self.derive { try SyncAccountKeys.passwordKeys(password: password, secretKey: secretKey, kdf: kdf) }
    }

    /// PBKDF2 (hundreds of thousands of iterations) off the main thread.
    @concurrent
    nonisolated static func derive<Result: Sendable>(_ work: @Sendable () throws -> Result) async throws -> Result {
        try work()
    }

    nonisolated static func unwrap(_ wrapped: Data, with key: SymmetricKey) throws -> SymmetricKey {
        do {
            return try SyncAccountKeys.unwrap(wrapped, with: key)
        } catch {
            throw SyncClientError.accountKeyUnreadable
        }
    }

    /// Envelopes of the account key and, for an account with a vault, of the vault root key, by a recovery key.
    nonisolated static func envelope(
        of keys: (account: SymmetricKey, vault: SymmetricKey?),
        for recoveryKey: SyncRecoveryKey,
    ) throws -> SyncKeyEnvelope {
        let recovery = SyncAccountKeys.recoveryKeys(recoveryKey)
        return try SyncKeyEnvelope(
            authKey: bytes(recovery.authKey),
            wrappedAccountKey: SyncAccountKeys.wrap(keys.account, with: recovery.wrapKey),
            wrappedVaultRootKey: keys.vault.map { try VaultCrypto.wrapRootKey($0, with: recovery.wrapKey) },
        )
    }

    nonisolated static func bytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}
