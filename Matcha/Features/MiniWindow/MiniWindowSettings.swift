import Foundation

/// Réglages de la barre d'une mini-fenêtre, lus dans `UserDefaults` à chaque ouverture (la vue les
/// suit ensuite avec `@AppStorage`). `bool(forKey:)` lit aussi les arguments de lancement « -clé NO »
/// des tests d'interface, que `object(forKey:) as? Bool` ne lit pas.
nonisolated enum MiniWindowSettings {
    static func current(_ defaults: UserDefaults = .standard) -> CommandBarSettings {
        let engine = defaults.string(forKey: BrowserSettings.Key.searchEngine).flatMap(SearchEngine.init(rawValue:))
        let key = BrowserSettings.Key.showsSearchSuggestions
        let suggestions = defaults.object(forKey: key) == nil ? BrowserSettings.showsSearchSuggestions : defaults.bool(forKey: key)
        return CommandBarSettings(
            searchEngine: engine ?? BrowserSettings.searchEngine,
            newTabPage: .blank,
            homePage: "",
            showsSearchSuggestions: suggestions,
        )
    }
}
