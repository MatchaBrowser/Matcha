import Foundation

/// What the command bar modifies when an address opens.
nonisolated enum CommandBarMode: Equatable, Sendable {
    /// Opening in a new tab (⌘T).
    case newTab
    /// Editing tab `UUID` of the displayed Space.
    case currentTab(UUID)
}
