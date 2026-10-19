import Foundation

/// History address, all visits grouped.
nonisolated struct HistoryEntry: Equatable, Sendable {
    let url: URL
    /// Last known non-empty title of the page.
    let title: String?
    let visitCount: Int
    let lastVisit: Date
}

/// History as seen by the bar (task 5.5): addresses grouped by URL, at most `limit`, a superset of what matches
/// `query`. Never read for a private session.
@MainActor
protocol HistorySource: AnyObject {
    func entries(matching query: CommandQuery, limit: Int) async -> [HistoryEntry]
}
