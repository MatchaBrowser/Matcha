import Foundation

/// Historique d'un profil vu par la barre de commande (`HistorySource`). Le profil est relu à chaque frappe : celui
/// du Space affiché par la fenêtre, ou celui d'une mini-fenêtre.
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
