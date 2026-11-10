import CryptoKit
import Foundation
import OSLog

/// The copy of the envelope of the vault root key kept on this Mac, with the derivation parameters of the account: the
/// vault opens with the password offline (`VAULT.md` § 7.1).
nonisolated struct SyncVaultEnvelope: Codable, Equatable, Sendable {
    var kdf: SyncKDF
    var wrappedVaultRootKey: Data
}

/// The keys of the vault in the account's flows (`VAULT.md` § 2.2): its envelopes change with those of the account
/// key, never one without the other. The vault root key is handed to the vault (`onVaultRootKey`) whenever a flow has
/// it, so that the vault opens without asking for the password again.
extension SyncService {
    /// The envelope this Mac keeps for the signed-in account; nil for an account without a vault.
    func storedVaultEnvelope() throws -> SyncVaultEnvelope? {
        guard let server = configuration.server, let accountID = configuration.accountID else {
            throw SyncClientError.signedOut
        }
        return try storedVaultEnvelope(server: server, accountID: accountID)
    }

    func storedVaultEnvelope(server: SyncServerAddress, accountID: UUID) throws -> SyncVaultEnvelope? {
        guard let data = try keychain.data(for: .vaultEnvelope, server: server, accountID: accountID) else {
            return nil
        }
        return try JSONDecoder().decode(SyncVaultEnvelope.self, from: data)
    }

    /// Opens the envelope of a session with `wrapKey` (`VAULT.md` § 7.1: at once, not at the first unlock), keeps it,
    /// and returns the vault root key; nil for an account without a vault. An envelope that doesn't open was replaced:
    /// it is not kept, and the vault says so.
    func keepVaultEnvelope(
        _ wrapped: Data?,
        kdf: SyncKDF,
        wrapKey: SymmetricKey,
        server: SyncServerAddress,
        accountID: UUID,
    ) throws -> SymmetricKey? {
        guard let wrapped else {
            keychain.removeAccount(server: server, accountID: accountID, items: [.vaultEnvelope])
            return nil
        }
        guard let vaultRootKey = try? VaultCrypto.unwrapRootKey(wrapped, with: wrapKey) else {
            Logger.sync.error("Unreadable vault envelope in the session: not kept")
            keychain.removeAccount(server: server, accountID: accountID, items: [.vaultEnvelope])
            isVaultEnvelopeUnreadable = true
            return nil
        }
        try storeVaultEnvelope(wrapped, kdf: kdf, server: server, accountID: accountID)
        return vaultRootKey
    }

    /// Keeps an envelope this Mac knows to be good.
    func storeVaultEnvelope(_ wrapped: Data, kdf: SyncKDF, server: SyncServerAddress, accountID: UUID) throws {
        let envelope = try JSONEncoder().encode(SyncVaultEnvelope(kdf: kdf, wrappedVaultRootKey: wrapped))
        try keychain.set(envelope, for: .vaultEnvelope, server: server, accountID: accountID)
        isVaultEnvelopeUnreadable = false
    }

    /// The vault root key from the kept envelope and the current `wrapKey`; nil for an account without a vault. The
    /// envelope was checked when it was kept: if it doesn't open, the password typed is wrong, as the server would
    /// say.
    func storedVaultRootKey(wrapKey: SymmetricKey) throws -> SymmetricKey? {
        guard let envelope = try storedVaultEnvelope() else {
            return nil
        }
        do {
            return try VaultCrypto.unwrapRootKey(envelope.wrappedVaultRootKey, with: wrapKey)
        } catch {
            throw SyncServerError(status: 401, code: SyncServerError.invalidCredentials)
        }
    }

    /// Starts the vault with the account sync just started.
    func activateVault(
        of account: (server: SyncServerAddress, accountID: UUID),
        client: SyncAPIClient,
        accountKey: SymmetricKey,
        deviceID: UUID,
    ) {
        let state = stateURL(server: account.server, accountID: account.accountID)
        vault?.syncDidActivate(SyncVaultAccount(
            server: account.server,
            accountID: account.accountID,
            client: client,
            identifiers: SyncIdentifiers(accountKey: accountKey),
            dataKey: SyncAccountKeys.dataKey(accountKey: accountKey),
            deviceID: deviceID,
            keychain: keychain,
            stateURL: VaultStateFile.url(nextTo: state),
            serverHasVault: configuration.serverInfo?.hasVault == true,
            requestCycle: { [weak self] in self?.coordinator?.syncSoon(after: .milliseconds(200)) },
            push: { body, key in try await client.push(body: body, key: key) },
            maxBlobBytes: configuration.serverInfo?.maximumBlobBytes ?? SyncServerInfo(api: 1).maximumBlobBytes,
        ))
    }

    /// Hands the vault root key of a flow to the vault.
    func vaultRootKeyArrived(_ key: SymmetricKey?) {
        if let key {
            onVaultRootKey?(key)
        }
    }

    nonisolated static func unwrapVault(_ wrapped: Data, with key: SymmetricKey) throws -> SymmetricKey {
        do {
            return try VaultCrypto.unwrapRootKey(wrapped, with: key)
        } catch {
            throw SyncClientError.vaultEnvelopeUnreadable
        }
    }
}
