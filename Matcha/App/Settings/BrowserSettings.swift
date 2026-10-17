import Foundation

/// Réglages du navigateur : clés dans `UserDefaults` et valeurs par défaut.
/// Les vues les lisent avec `@AppStorage(BrowserSettings.Key…)`.
nonisolated enum BrowserSettings {
    enum Key {
        static let searchEngine = "searchEngine"
        static let appearance = "appearance"
        static let confirmBeforeQuitting = "confirmBeforeQuitting"
        static let homePage = "homePage"
        static let newTabPage = "newTabPage"
        static let showsHomeButton = "showsHomeButton"
        static let addressBarPosition = "addressBarPosition"
        static let showsNavigationButtons = "showsNavigationButtons"
        static let showsSearchSuggestions = "showsSearchSuggestions"
    }

    static let searchEngine = SearchEngine.defaultEngine
    static let appearance = AppearanceMode.system
    /// Tant que les onglets ne sont pas restaurés au lancement (phase 3), quitter les perd.
    static let confirmBeforeQuitting = true
    /// Page d'accueil telle que saisie ; vide tant qu'elle n'est pas choisie.
    static let homePage = ""
    static let newTabPage = NewTabPage.blank
    static let showsHomeButton = false
    static let addressBarPosition = AddressBarPosition.sidebar
    static let showsNavigationButtons = true
    /// Suggestions du moteur de recherche dans la barre de commande (jamais en fenêtre privée).
    static let showsSearchSuggestions = true

    /// Adresse de la page d'accueil saisie dans les réglages, interprétée comme dans la barre d'adresse ;
    /// nil si elle est vide.
    static func homeURL(from text: String, searchEngine: SearchEngine) -> URL? {
        AddressResolver(searchEngine: searchEngine).resolve(text)
    }

    /// Valeur de l'alerte avant de quitter dans `defaults`, ou sa valeur par défaut.
    static func confirmsBeforeQuitting(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.confirmBeforeQuitting) as? Bool ?? confirmBeforeQuitting
    }
}
