import Foundation

/// Source of command bar results. It returns broadly: `CommandRanker` alone does the matching with the text. Never
/// called for an empty text or for the unmodified ⌘L address.
/// A cancelled task returns quickly, possibly with [] (the model then ignores its result).
@MainActor
protocol CommandProvider: AnyObject {
    func candidates(for query: CommandQuery, context: CommandContext) async -> [CommandCandidate]
}

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
