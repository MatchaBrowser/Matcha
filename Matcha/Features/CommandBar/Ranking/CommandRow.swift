import Foundation

/// Effet d'une ligne de la barre de commande.
nonisolated enum CommandTarget: Equatable, Sendable {
    /// Ouvrir l'adresse dans l'onglet visé, ou dans un nouvel onglet.
    case open(URL)
    case switchToTab(TabReference)
    case perform(CommandActionID)
}

/// Ligne affichée par la barre de commande.
nonisolated struct CommandRow: Identifiable, Equatable, Sendable {
    enum Style: Equatable, Sendable {
        /// Ouvrir le texte tapé lu comme une adresse, ou l'adresse de ⌘L non modifiée.
        case openAddress
        /// Rechercher le texte tapé.
        case search
        /// Rechercher un nom de domaine tapé seul, en 2e ligne.
        case searchAlternative
        /// `spaceName` est nil pour un onglet du Space affiché.
        case tab(TabReference, place: TabPlace, spaceName: String?)
        case history
        case suggestion
        case action(CommandActionID)
    }

    let id: String
    let style: Style
    /// Donnée affichée telle quelle (adresse, titre de page, suggestion) ; les titres des actions
    /// sont déjà traduits par leur source.
    let title: String
    /// Adresse affichée sous le titre, s'il y en a une. Les sous-titres traduits (« Search %@ »)
    /// sont produits par la vue d'après `style`.
    let subtitle: String?
    /// Adresse ouverte ou montrée par la ligne ; nil pour les actions.
    let url: URL?
    let target: CommandTarget
}
