import Foundation

/// What follows Return or a click on a row.
nonisolated enum CommandBarSubmission: Equatable, Sendable {
    /// Run the row's target, in the bar's mode.
    case run(CommandTarget, mode: CommandBarMode)
    /// Return with no text in new tab mode: an empty tab.
    case openEmptyTab
    /// Nothing to do: the bar stays open.
    case ignore
}
