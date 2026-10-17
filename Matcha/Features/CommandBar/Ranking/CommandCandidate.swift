import Foundation

/// Onglet d'un Space de la fenêtre, désigné par identifiants : la barre ne garde pas d'objet vivant.
nonisolated struct TabReference: Hashable, Sendable {
    let tabID: UUID
    let spaceID: UUID
}

/// Actions proposées par la barre de commande, dans leur ordre d'affichage à égalité.
nonisolated enum CommandActionID: String, CaseIterable, Sendable {
    case newSpace
    case copyURL
    case settings
}

/// Résultat brut fourni par une source de la barre, avant correspondance et classement.
nonisolated struct CommandCandidate: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Onglet ouvert ; `spaceName` est nil pour le Space affiché.
        case tab(TabReference, place: TabPlace, spaceName: String?, lastActivity: Date)
        /// Adresse de l'historique, toutes visites regroupées.
        case history(visitCount: Int, lastVisit: Date)
        /// `keywords` : mots cherchés en plus du titre, jamais affichés.
        case action(CommandActionID, keywords: [String])
        /// Suggestion du moteur de recherche ; le titre est le texte à chercher.
        case suggestion
    }

    let kind: Kind
    let title: String
    /// Nil pour les actions et les suggestions.
    let url: URL?

    /// Identifiant stable, repris par la ligne affichée : `tab:<uuid>`, `history:<clé d'adresse>`,
    /// `action:<nom>`, `suggestion:<texte replié>`.
    var id: String {
        switch kind {
        case let .tab(reference, _, _, _): "tab:\(reference.tabID.uuidString)"
        case .history: "history:\(url.map(CommandText.urlKey) ?? "")"
        case let .action(action, _): "action:\(action.rawValue)"
        case .suggestion: "suggestion:\(CommandText.fold(title))"
        }
    }
}
