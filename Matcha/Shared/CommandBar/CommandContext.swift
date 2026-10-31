import Foundation

/// What the sources know about the current opening.
nonisolated struct CommandContext: Equatable, Sendable {
    var isPrivate = false
    var showsSearchSuggestions = false
    /// Engine asked for suggestions; nil: the search engine of the query (review A7).
    var suggestionEngine: SearchEngine?

    /// Engine suggestions allowed: setting enabled and window not private.
    var allowsSuggestions: Bool {
        showsSearchSuggestions && !isPrivate
    }
}
