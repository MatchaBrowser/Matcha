import Foundation

/// What the sources know about the current opening.
nonisolated struct CommandContext: Equatable, Sendable {
    var isPrivate = false
    var showsSearchSuggestions = false

    /// Engine suggestions allowed: setting enabled and window not private.
    var allowsSuggestions: Bool {
        showsSearchSuggestions && !isPrivate
    }
}
