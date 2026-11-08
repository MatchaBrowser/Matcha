import Foundation

/// The account's Secret Key in this Mac's keychain (`SYNC.md` § 3.8): kept with the account key, it outlives a session
/// ended by the server, so that the same account signs in again with its password only; it leaves at the sign-out and
/// with the account.
extension SyncService {
    /// The Secret Key this Mac kept for the account it was signed in to: the sign-in form starts with it. Nil without
    /// one, or if the keychain refuses.
    func rememberedSecretKey() -> SyncSecretKey? {
        guard let server = configuration.server, let accountID = configuration.accountID,
              let bytes = try? keychain.data(for: .secretKey, server: server, accountID: accountID)
        else {
            return nil
        }
        return SyncSecretKey(bytes: bytes)
    }

    /// The signed-in account's Secret Key, which its sensitive operations need.
    func storedSecretKey() throws -> SyncSecretKey {
        guard let server = configuration.server, let accountID = configuration.accountID,
              let bytes = try keychain.data(for: .secretKey, server: server, accountID: accountID),
              let secretKey = SyncSecretKey(bytes: bytes)
        else {
            throw SyncClientError.signedOut
        }
        return secretKey
    }

    /// Keeps the Secret Key of the account being signed in to. The one of another account, kept from an ended session,
    /// no longer has a use.
    func keepSecretKey(_ secretKey: SyncSecretKey, server: SyncServerAddress, accountID: UUID) throws {
        let isAnotherAccount = configuration.server != server || configuration.accountID != accountID
        if isAnotherAccount, let previousServer = configuration.server, let previousAccount = configuration.accountID {
            keychain.removeAccount(server: previousServer, accountID: previousAccount, items: [.secretKey])
        }
        try keychain.set(secretKey.bytes, for: .secretKey, server: server, accountID: accountID)
    }
}
