import Foundation
import OSLog

/// Touch ID for the vault of the signed-in account (`VAULT.md` § 7.2): offered at the first unlock with the password;
/// the password is asked again after 14 days, after a restart, and for exports.
extension VaultService {
    var isTouchIDAvailable: Bool {
        VaultTouchID.isAvailable
    }

    var isTouchIDEnabled: Bool {
        (try? touchIDEnvelope()) != nil
    }

    private func touchIDEnvelope() throws -> VaultTouchID.Envelope? {
        guard let account,
              let data = try account.keychain.data(for: .vaultTouchID, server: account.server, accountID: account.accountID)
        else {
            return nil
        }
        return try JSONDecoder().decode(VaultTouchID.Envelope.self, from: data)
    }

    /// Wraps the open vault's root key for this Mac's Secure Enclave.
    func enableTouchID() throws {
        guard let session, let account else {
            throw VaultError.locked
        }
        let envelope = try VaultTouchID.wrap(session.rootKey)
        try account.keychain.set(JSONEncoder().encode(envelope), for: .vaultTouchID, server: account.server, accountID: account.accountID)
    }

    /// “Forget the Vault on This Mac” (`VAULT.md` § 5.5): its state and its Touch ID go; the vault comes back from the
    /// server at the next unlock, and this Mac verifies it as a new one.
    func forgetLocalVault() {
        lock()
        disableTouchID()
        file.delete()
        state = VaultState()
        refreshStatus()
    }

    func disableTouchID() {
        guard let account else {
            return
        }
        account.keychain.removeAccount(server: account.server, accountID: account.accountID, items: [.vaultTouchID])
    }

    /// Whether Touch ID may open the vault now: enabled, available, and the password not due.
    func canUnlockWithTouchID(bootDate: Date) -> Bool {
        isTouchIDEnabled && isTouchIDAvailable && !needsPassword(bootDate: bootDate)
    }

    /// Opens the vault with the fingerprint. Fingerprints changed: the envelope is deleted, the password is needed.
    func unlockWithTouchID(reason: String) async throws {
        guard isEnabled, let envelope = try touchIDEnvelope() else {
            throw VaultTouchID.Failure.unavailable
        }
        do {
            let rootKey = try await VaultTouchID.unwrap(envelope, reason: reason)
            await open(rootKey: rootKey)
        } catch VaultTouchID.Failure.invalidated {
            Logger.vault.notice("Touch ID key of the vault invalidated: password needed")
            disableTouchID()
            throw VaultTouchID.Failure.invalidated
        }
    }
}
