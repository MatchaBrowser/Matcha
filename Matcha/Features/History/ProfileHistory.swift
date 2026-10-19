import Foundation

/// A profile's history as seen by the command bar (`HistorySource`). The profile is read again on each keystroke:
/// that of the Space displayed by the window, or that of a mini window.
@MainActor
final class ProfileHistory: HistorySource {
    private let store: HistoryStore
    private let profileID: () -> UUID?

    init(store: HistoryStore, profileID: @escaping () -> UUID?) {
        self.store = store
        self.profileID = profileID
    }

    convenience init(store: HistoryStore, profileID: UUID?) {
        self.init(store: store) { profileID }
    }

    func entries(matching query: CommandQuery, limit: Int) async -> [HistoryEntry] {
        await store.entries(profileID: profileID(), matching: query, limit: limit)
    }
}
