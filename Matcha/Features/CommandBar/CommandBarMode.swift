import Foundation

/// What the command bar modifies when an address opens.
nonisolated enum CommandBarMode: Equatable, Sendable {
    /// Opening in a new tab (⌘T).
    case newTab
    /// Editing tab `UUID` of the displayed Space.
    case currentTab(UUID)
}

/// What the sources know about the current opening.
nonisolated struct CommandContext: Equatable, Sendable {
    var isPrivate = false
    var showsSearchSuggestions = false

    /// Engine suggestions allowed: setting enabled and window not private.
    var allowsSuggestions: Bool {
        showsSearchSuggestions && !isPrivate
    }
}

/// Settings read by the window (@AppStorage) each time the bar opens, then followed as long as it stays open
/// (`CommandBarModel.apply`).
nonisolated struct CommandBarSettings: Equatable, Sendable {
    var searchEngine: SearchEngine
    /// Page of new tabs: nil = command bar then empty tab.
    var newTabHomeURL: URL?
    var showsSearchSuggestions: Bool

    /// `newTabHomeURL` = `BrowserSettings.homeURL(from: homePage, searchEngine:)` only if
    /// `newTabPage == .homePage`.
    init(searchEngine: SearchEngine, newTabPage: NewTabPage, homePage: String, showsSearchSuggestions: Bool) {
        self.searchEngine = searchEngine
        newTabHomeURL = newTabPage == .homePage ? BrowserSettings.homeURL(from: homePage, searchEngine: searchEngine) : nil
        self.showsSearchSuggestions = showsSearchSuggestions
    }
}

/// What follows Return or a click on a row.
nonisolated enum CommandBarSubmission: Equatable, Sendable {
    /// Run the row's target, in the bar's mode.
    case run(CommandTarget, mode: CommandBarMode)
    /// Return with no text in new tab mode: an empty tab.
    case openEmptyTab
    /// Nothing to do: the bar stays open.
    case ignore
}
