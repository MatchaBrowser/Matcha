import Foundation

/// A visit kept in memory by `HistoryIndex`: the copy of a `HistoryRecord`, without its profile (the index belongs
/// to one profile).
nonisolated struct HistoryVisit: Equatable, Sendable {
    let id: UUID
    /// Kept address (`HistoryRecordingPolicy.storedURL`).
    let url: URL
    /// `CommandText.urlKey(url)`: visits with the same key are the same page.
    let urlKey: String
    /// Non-empty title, or nil (`HistoryRecordingPolicy.normalizedTitle`).
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
