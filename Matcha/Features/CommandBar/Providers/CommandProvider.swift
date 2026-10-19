import Foundation

/// Source of command bar results. It returns broadly: `CommandRanker` alone does the matching with the text. Never
/// called for an empty text or for the unmodified ⌘L address.
/// A cancelled task returns quickly, possibly with [] (the model then ignores its result).
@MainActor
protocol CommandProvider: AnyObject {
    func candidates(for query: CommandQuery, context: CommandContext) async -> [CommandCandidate]
}
