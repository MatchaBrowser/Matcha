import Foundation
import OSLog

/// File of the vault's state (JSON), one per server and account (`vault-<digest>.json`, next to the sync state);
/// without a URL (tests), nothing is written. It outlives the session (`VAULT.md` § 5.5): only an explicit sign-out or
/// deletion from this Mac deletes it. An unreadable file is set aside, renamed, rather than overwritten.
nonisolated struct VaultStateFile: Sendable {
    let url: URL?

    /// The file of an account, next to `stateURL` (`state-<digest>.json` → `vault-<digest>.json`).
    static func url(nextTo stateURL: URL?) -> URL? {
        stateURL.map { url in
            url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent.replacingOccurrences(of: "state-", with: "vault-"))
        }
    }

    func load() -> VaultState {
        guard let url else {
            return VaultState()
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return VaultState()
        } catch {
            Logger.vault.error("Vault state unreadable: \(error.logSummary, privacy: .public)")
            return VaultState()
        }
        do {
            return try SyncCoding.decoder().decode(VaultState.self, from: data)
        } catch {
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            Logger.vault.error("Unreadable vault state set aside")
            return VaultState()
        }
    }

    func save(_ state: VaultState) throws {
        guard let url else {
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyncCoding.encoder().encode(state).write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Sign-out or deletion of the account from this Mac.
    func delete() {
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
