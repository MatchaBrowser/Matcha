import Foundation

/// Settings read by the window (@AppStorage) each time the bar opens, then followed as long as it stays open
/// (`CommandBarModel.apply`).
nonisolated struct CommandBarSettings: Equatable, Sendable {
    var searchEngine: SearchEngine
    /// Page of new tabs: nil = command bar then empty tab.
    var newTabHomeURL: URL?
    var showsSearchSuggestions: Bool
    /// Engine asked for suggestions (review A7): the search engine, or the one chosen for them.
    var suggestionEngine: SearchEngine

    /// `newTabHomeURL` = `BrowserSettings.homeURL(from: homePage, searchEngine:)` only if
    /// `newTabPage == .homePage`.
    init(
        searchEngine: SearchEngine,
        newTabPage: NewTabPage,
        homePage: String,
        showsSearchSuggestions: Bool,
        suggestionSource: SuggestionSource = .defaultSource,
    ) {
        self.searchEngine = searchEngine
        newTabHomeURL = newTabPage == .homePage ? BrowserSettings.homeURL(from: homePage, searchEngine: searchEngine) : nil
        self.showsSearchSuggestions = showsSearchSuggestions
        suggestionEngine = suggestionSource.engine(for: searchEngine)
    }
}
