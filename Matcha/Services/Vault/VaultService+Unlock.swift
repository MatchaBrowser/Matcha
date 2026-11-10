import CryptoKit
import Foundation
import OSLog

/// Opening and locking the vault (`VAULT.md` § 7.1 and § 7.3): with the master password and the Secret Key, offline,
/// against the copy of the envelope; with the key an account flow hands over; locked after a delay without use, at
/// sleep, at the screen lock, and on demand.
extension VaultService {
    /// After 5 wrong passwords, each attempt waits 30 s more, up to 5 minutes.
    static let freeAttempts = 5
    static let attemptDelay: TimeInterval = 30
    static let maximumAttemptDelay: TimeInterval = 5 * 60
    /// Automatic lock after this long without use, by default (`VAULT.md` § 7.3); 0: never while the Mac is awake.
    static let defaultLockDelay: TimeInterval = 15 * 60
    static let lockDelayKey = "vaultLockDelay"
    static let lockDelays: [TimeInterval] = [60, 5 * 60, 15 * 60, 30 * 60, 60 * 60, 0]
    /// Last opening with the password: Touch ID asks for it again after 14 days and after a restart (`VAULT.md` § 7.2).
    static let passwordUnlockKey = "vaultPasswordUnlockedAt"

    var lockDelay: TimeInterval {
        defaults.object(forKey: Self.lockDelayKey) as? TimeInterval ?? Self.defaultLockDelay
    }

    func setLockDelay(_ delay: TimeInterval) {
        defaults.set(delay, forKey: Self.lockDelayKey)
        scheduleLock()
    }

    /// Opens the vault with the master password: PBKDF2 off the main thread, then the copy of the envelope.
    func unlock(password: String) async throws {
        guard isEnabled, let account else {
            throw VaultError.unavailable
        }
        if let blocked = attemptsBlockedUntil, blocked > now() {
            throw VaultError.tooManyAttempts(until: blocked)
        }
        guard let envelope = try envelope(),
              let secretData = try account.keychain.data(for: .secretKey, server: account.server, accountID: account.accountID),
              let secretKey = SyncSecretKey(bytes: secretData)
        else {
            throw VaultError.unavailable
        }
        let keys = try await SyncService.derive {
            try SyncAccountKeys.passwordKeys(password: password, secretKey: secretKey, kdf: envelope.kdf)
        }
        guard let rootKey = try? VaultCrypto.unwrapRootKey(envelope.wrappedVaultRootKey, with: keys.wrapKey) else {
            failedAttempt()
            throw VaultError.wrongPassword
        }
        failedAttempts = 0
        attemptsBlockedUntil = nil
        defaults.set(now(), forKey: Self.passwordUnlockKey)
        await open(rootKey: rootKey)
    }

    private func failedAttempt() {
        failedAttempts += 1
        let extra = failedAttempts - Self.freeAttempts
        guard extra > 0 else {
            return
        }
        let delay = min(Self.maximumAttemptDelay, Double(extra) * Self.attemptDelay)
        attemptsBlockedUntil = now().addingTimeInterval(delay)
    }

    /// Opens the vault with its root key: from an account flow, from Touch ID, or after the password.
    func open(rootKey: SymmetricKey) async {
        guard isEnabled, account != nil else {
            return
        }
        let session = VaultSession(vaultRootKey: rootKey)
        if let vaultID = state.vaultID, vaultID != session.keys.vaultID {
            // A state of another vault (an account recreated with the same identifier): it can't be verified here.
            Logger.vault.error("Vault state of another vault set aside")
            state = VaultState()
        }
        state.vaultID = session.keys.vaultID
        self.session = session
        noteActivity()
        refreshStatus()
        rebuildItems()
        scheduleLock()
        if let serverState {
            await verifyAndWrite(serverState)
        } else {
            account?.requestCycle()
        }
    }

    /// Forgets the keys and everything opened (`VAULT.md` § 7.3).
    func lock() {
        guard session != nil else {
            return
        }
        session = nil
        lockTask?.cancel()
        lockTask = nil
        items = []
        deleteOpenedFiles()
        refreshStatus()
        for forget in onLock {
            forget()
        }
        Logger.vault.info("Vault locked")
    }

    /// Locks after the delay without use; checked again until it passes.
    func scheduleLock() {
        lockTask?.cancel()
        let delay = lockDelay
        guard session != nil, delay > 0 else {
            return
        }
        lockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                let idle = now().timeIntervalSince(lastActivity)
                if idle >= delay {
                    lock()
                    return
                }
                try? await Task.sleep(for: .seconds(max(1, delay - idle)))
            }
        }
    }

    /// Whether Touch ID may open the vault now, or the password is due: after 14 days, or after a restart.
    func needsPassword(bootDate: Date) -> Bool {
        guard let last = defaults.object(forKey: Self.passwordUnlockKey) as? Date else {
            return true
        }
        return last < bootDate || now().timeIntervalSince(last) > 14 * 24 * 3600
    }
}
