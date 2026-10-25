import Foundation

/// Source of command bar results. It returns broadly: `CommandRanker` alone does the matching with the text. Never
/// called for an empty text or for the unmodified ⌘L address.
/// A cancelled task returns quickly, possibly with [] (the model then ignores its result).
@MainActor
protocol CommandProvider: AnyObject {
    /// True for a source that answers at once, from memory (open tabs, actions): those are ranked together, in a
    /// single pass, before the slower ones are awaited (review IU2).
    var answersAtOnce: Bool { get }

    func candidates(for query: CommandQuery, context: CommandContext) async -> [CommandCandidate]
}

extension CommandProvider {
    var answersAtOnce: Bool {
        false
    }
}
