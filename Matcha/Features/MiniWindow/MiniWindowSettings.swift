import Foundation

/// Settings of a mini window's bar, read from `UserDefaults` at each opening (the view then
/// follows them with `@AppStorage`). `bool(forKey:)` also reads the UI tests' “-key NO” launch
/// arguments, which `object(forKey:) as? Bool` does not read.
nonisolated enum MiniWindowSettings {
    static func current(_ defaults: UserDefaults = .standard) -> CommandBarSettings {
        let engine = defaults.string(forKey: BrowserSettings.Key.searchEngine).flatMap(SearchEngine.init(rawValue:))
        let key = BrowserSettings.Key.showsSearchSuggestions
        let suggestions = defaults.object(forKey: key) == nil ? BrowserSettings.showsSearchSuggestions : defaults.bool(forKey: key)
        let source = defaults.string(forKey: BrowserSettings.Key.searchSuggestionSource).flatMap(SuggestionSource.init(rawValue:))
        return CommandBarSettings(
            searchEngine: engine ?? BrowserSettings.searchEngine,
            newTabPage: .blank,
            homePage: "",
            showsSearchSuggestions: suggestions,
            suggestionSource: source ?? BrowserSettings.searchSuggestionSource,
        )
    }
}
