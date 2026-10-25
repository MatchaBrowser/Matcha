import CryptoKit
import Foundation

/// Questions to the user, this Mac's identity and sync state files.
extension SyncService {
    // MARK: Device

    /// This Mac's device identifier, drawn the first time and kept in the keychain with the machine's mark; `isNew`
    /// when it was just drawn again because the mark changed (copied Mac).
    func deviceIdentity() throws -> (id: UUID, isNew: Bool) {
        let mark = SyncMachineMark.current()
        if let device = try keychain.device() {
            if device.machineMark == nil || mark == nil || device.machineMark == mark {
                if device.machineMark == nil, let mark {
                    try keychain.setDevice(SyncKeychain.Device(id: device.id, machineMark: mark))
                }
                return (device.id, false)
            }
            let copy = SyncKeychain.Device(id: UUID(), machineMark: mark)
            try keychain.setDevice(copy)
            return (copy.id, true)
        }
        let device = SyncKeychain.Device(id: UUID(), machineMark: mark)
        try keychain.setDevice(device)
        return (device.id, false)
    }

    // MARK: Questions

    func askFirstSync() async -> SyncEngine.FirstSyncChoice {
        guard case let .firstSync(choice) = await ask(.firstSync) else {
            return .merge
        }
        return choice
    }

    func askRecreations(_ count: Int) async -> SyncEngine.RecreationChoice {
        guard case let .recreations(choice) = await ask(.recreations(count: count)) else {
            return .sendAgain
        }
        return choice
    }

    func confirm(_ kind: SyncQuestion.Kind) async -> Bool {
        guard case let .massDeletion(confirmed) = await ask(kind) else {
            return false
        }
        return confirmed
    }

    func ask(_ kind: SyncQuestion.Kind) async -> SyncQuestion.Answer {
        await withCheckedContinuation { continuation in
            question = SyncQuestion(kind: kind) { continuation.resume(returning: $0) }
        }
    }

    /// The user's answer to the pending question.
    func answer(_ answer: SyncQuestion.Answer) {
        let pending = question
        question = nil
        pending?.answer(answer)
    }

    // MARK: Files

    /// State file of an account: its name hides the server and the account (`state-<digest>.json`).
    func stateURL(server: SyncServerAddress, accountID: UUID) -> URL? {
        let digest = SHA256.hash(data: Data("\(server.normalized)|\(accountID.uuidString.lowercased())".utf8))
        let name = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent("state-\(name).json")
    }

    /// Extensions file of an account (`extensions-<digest>.json`, review SY11).
    func extensionsURL(server: SyncServerAddress, accountID: UUID) -> URL? {
        stateURL(server: server, accountID: accountID).map { url in
            url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent.replacingOccurrences(
                of: "state-",
                with: "extensions-",
            ))
        }
    }

    /// States (and extensions files) no longer used for 60 days: copies in clear text of part of the data, deleted.
    func removeUnusedStates(keeping current: URL?) {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
        ) else {
            return
        }
        let limit = Date.now.addingTimeInterval(-Self.unusedStateLifetime)
        let kept = current.map { current in
            [current.lastPathComponent, current.lastPathComponent.replacingOccurrences(of: "state-", with: "extensions-")]
        } ?? []
        let isSyncFile = { (name: String) in name.hasPrefix("state-") || name.hasPrefix("extensions-") }
        for file in files where isSyncFile(file.lastPathComponent) && !kept.contains(file.lastPathComponent) {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < limit {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
