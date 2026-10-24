import CryptoKit
import Foundation

/// Questions to the user and sync state files.
extension SyncService {
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

    /// States no longer used for 60 days: copies in clear text of part of the data, deleted.
    func removeUnusedStates(keeping current: URL?) {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
        ) else {
            return
        }
        let limit = Date.now.addingTimeInterval(-Self.unusedStateLifetime)
        for file in files where file.lastPathComponent.hasPrefix("state-") && file != current {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < limit {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
