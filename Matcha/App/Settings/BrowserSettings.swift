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
        static let opensPinnedLinksInPeek = "opensPinnedLinksInPeek"
        static let tabSuspensionDelay = "tabSuspensionDelay"
        static let blocksAdsAndTrackers = "blocksAdsAndTrackers"
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
    /// Liens d'un favori ou d'un épinglé vers un autre site ouverts dans l'aperçu (tâche 4.4), comme dans Arc ;
    /// désactivé par défaut : un clic ordinaire garde son comportement tant qu'on ne l'a pas choisi.
    static let opensPinnedLinksInPeek = false
    /// Mémoire libérée après 30 minutes sans affichage (tâche 5.6).
    static let tabSuspensionDelay = TabSuspensionDelay.thirtyMinutes
    /// Bloqueur de publicités et de traqueurs (tâche 6.2), actif dès que des listes sont livrées.
    static let blocksAdsAndTrackers = true

    /// Adresse de la page d'accueil saisie dans les réglages, interprétée comme dans la barre d'adresse ;
    /// nil si elle est vide.
    static func homeURL(from text: String, searchEngine: SearchEngine) -> URL? {
        AddressResolver(searchEngine: searchEngine).resolve(text)
    }

    /// Valeur de l'alerte avant de quitter dans `defaults`, ou sa valeur par défaut.
    static func confirmsBeforeQuitting(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.confirmBeforeQuitting) as? Bool ?? confirmBeforeQuitting
    }

    /// Valeur du réglage de l'aperçu dans `defaults`, ou sa valeur par défaut. `bool(forKey:)` lit aussi les
    /// « YES » et « NO » des arguments de lancement (`as? Bool` les ignore).
    static func pinnedLinksOpenInPeek(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.opensPinnedLinksInPeek) == nil
            ? opensPinnedLinksInPeek
            : defaults.bool(forKey: Key.opensPinnedLinksInPeek)
    }

    /// Délai de mise en veille des onglets cachés dans `defaults` (minutes, nombre ou texte d'un argument de lancement
    /// comme « -tabSuspensionDelay 0 »), ou sa valeur par défaut si la valeur manque ou n'est pas une option.
    static func tabSuspensionDelay(in defaults: UserDefaults = .standard) -> TabSuspensionDelay {
        let stored = defaults.object(forKey: Key.tabSuspensionDelay)
        let minutes = (stored as? NSNumber)?.intValue ?? (stored as? String).flatMap { Int($0) }
        return minutes.flatMap(TabSuspensionDelay.init(rawValue:)) ?? tabSuspensionDelay
    }

    /// Valeur du réglage du bloqueur dans `defaults` (« YES » et « NO » des arguments de lancement compris), ou sa
    /// valeur par défaut ; sans réglages (tests), la valeur par défaut.
    static func blocksAdsAndTrackers(in defaults: UserDefaults?) -> Bool {
        guard let defaults, defaults.object(forKey: Key.blocksAdsAndTrackers) != nil else {
            return blocksAdsAndTrackers
        }
        return defaults.bool(forKey: Key.blocksAdsAndTrackers)
    }
}
