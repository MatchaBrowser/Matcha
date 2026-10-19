import Foundation

/// Link peek (task 4.4): a page opened over the displayed pages, in its own web view, from the same profile.
/// Outside the sidebar and never saved, until “Open as Tab”.
struct Peek: Identifiable {
    /// Unfiled tab that owns the peek's web view; it becomes the opened tab.
    let tab: BrowserTab
    /// Tab over which the peek is shown; showing another one closes the peek.
    let sourceTabID: BrowserTab.ID
    /// Point the peek grows from, as fractions of the pages area (0…1, origin at the top left).
    let openingPoint: CGPoint

    var id: BrowserTab.ID {
        tab.id
    }
}
