import Foundation

/// Historique vu par les pages d'un Space (onglets et aperçu) ou d'une mini-fenêtre (sans Space) : où et pour quel
/// profil retenir leurs visites. Absent pour une fenêtre privée.
struct HistoryScope {
    let store: HistoryStore
    let profileID: UUID?
    let spaceID: UUID?
}
