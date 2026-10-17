import Foundation

/// Ce que la barre de commande modifie quand une adresse s'ouvre.
nonisolated enum CommandBarMode: Equatable, Sendable {
    /// Ouverture dans un nouvel onglet (⌘T).
    case newTab
    /// Édition de l'onglet `UUID` du Space affiché.
    case currentTab(UUID)
}

/// Ce que les sources savent de l'ouverture en cours.
nonisolated struct CommandContext: Equatable, Sendable {
    var isPrivate = false
    var showsSearchSuggestions = false

    /// Suggestions du moteur permises : réglage activé et fenêtre non privée.
    var allowsSuggestions: Bool {
        showsSearchSuggestions && !isPrivate
    }
}

/// Réglages lus par la fenêtre (@AppStorage) à chaque ouverture de la barre, puis suivis tant
/// qu'elle reste ouverte (`CommandBarModel.apply`).
nonisolated struct CommandBarSettings: Equatable, Sendable {
    var searchEngine: SearchEngine
    /// Page des nouveaux onglets : nil = barre de commande puis onglet vide.
    var newTabHomeURL: URL?
    var showsSearchSuggestions: Bool

    /// `newTabHomeURL` = `BrowserSettings.homeURL(from: homePage, searchEngine:)` seulement si
    /// `newTabPage == .homePage`.
    init(searchEngine: SearchEngine, newTabPage: NewTabPage, homePage: String, showsSearchSuggestions: Bool) {
        self.searchEngine = searchEngine
        newTabHomeURL = newTabPage == .homePage ? BrowserSettings.homeURL(from: homePage, searchEngine: searchEngine) : nil
        self.showsSearchSuggestions = showsSearchSuggestions
    }
}

/// Suite donnée à Entrée ou à un clic sur une ligne.
nonisolated enum CommandBarSubmission: Equatable, Sendable {
    /// Exécuter la cible de la ligne, dans le mode de la barre.
    case run(CommandTarget, mode: CommandBarMode)
    /// Entrée sans texte en mode nouvel onglet : un onglet vide.
    case openEmptyTab
    /// Rien à faire : la barre reste ouverte.
    case ignore
}
