import Foundation

/// A question sync asks the user before going on (`SYNC.md` § 5); the cycle waits for the answer.
@MainActor
final class SyncQuestion: Identifiable {
    enum Kind: Equatable {
        /// First sync: this Mac and the synced data each have their own data.
        case firstSync
        /// `count` deletions, more than half of the account, about to leave.
        case massDeletion(count: Int)
        /// The server no longer knows `count` records of this Mac (expired cursor).
        case recreations(count: Int)
    }

    enum Answer: Equatable {
        case firstSync(SyncEngine.FirstSyncChoice)
        case massDeletion(confirmed: Bool)
        case recreations(SyncEngine.RecreationChoice)
    }

    let id = UUID()
    let kind: Kind
    private var reply: ((Answer) -> Void)?

    init(kind: Kind, reply: @escaping (Answer) -> Void) {
        self.kind = kind
        self.reply = reply
    }

    /// Answers once; the next answers are ignored.
    func answer(_ answer: Answer) {
        reply?(answer)
        reply = nil
    }

    /// The safe default: merge, keep the records, send them again.
    func answerByDefault() {
        switch kind {
        case .firstSync: answer(.firstSync(.merge))
        case .massDeletion: answer(.massDeletion(confirmed: false))
        case .recreations: answer(.recreations(.sendAgain))
        }
    }
}
