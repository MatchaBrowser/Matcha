import Foundation

/// Visite gardée en mémoire par `HistoryIndex` : la copie d'un `HistoryRecord`, sans son profil (l'index est celui
/// d'un profil).
nonisolated struct HistoryVisit: Equatable, Sendable {
    let id: UUID
    /// Adresse retenue (`HistoryRecordingPolicy.storedURL`).
    let url: URL
    /// `CommandText.urlKey(url)` : les visites de même clé sont la même page.
    let urlKey: String
    /// Titre non vide, ou nil (`HistoryRecordingPolicy.normalizedTitle`).
    var title: String?
    var date: Date

    init(id: UUID = UUID(), url: URL, urlKey: String? = nil, title: String?, date: Date) {
        self.id = id
        self.url = url
        self.urlKey = urlKey ?? CommandText.urlKey(url)
        self.title = HistoryRecordingPolicy.normalizedTitle(title)
        self.date = date
    }
}
