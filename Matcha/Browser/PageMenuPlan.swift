import Foundation

/// Éléments du menu contextuel de WebKit que Matcha remplace (tâche 5.9). Leurs identifiants (`NSMenuItem.identifier`)
/// ne sont pas documentés : aucun en-tête public du SDK de macOS 27 ne les déclare. Valeurs relevées sur un vrai menu
/// de WebKit (`PageMenuIntegrationTests`) ; si WebKit les change, son élément reste tel quel.
nonisolated enum WebKitMenuItem: String, CaseIterable, Sendable {
    case openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
    case openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
}

/// Élément de Matcha dans le menu contextuel des pages.
nonisolated enum PageMenuItem: String, Equatable, Sendable {
    /// « Ouvrir le lien dans un nouvel onglet », à la place de « … dans une nouvelle fenêtre ».
    case openLinkInNewTab = "OpenLinkInNewTab"
    /// « Ouvrir dans un aperçu », juste après.
    case openLinkInPeek = "OpenLinkInPeek"
    /// « Ouvrir l'image dans un nouvel onglet », à la place de « … dans une nouvelle fenêtre ».
    case openImageInNewTab = "OpenImageInNewTab"

    /// Identifiant de l'élément de menu, sur le modèle de ceux de WebKit (sans lui, AppKit donne le nom de l'action).
    var identifier: String {
        "MatchaMenuItemIdentifier" + rawValue
    }

    /// Ce que devient la fenêtre que WebKit ouvre pour ce choix.
    var destination: PageMenuDestination {
        switch self {
        case .openLinkInNewTab, .openImageInNewTab:
            .backgroundTab
        case .openLinkInPeek:
            .peek
        }
    }
}

/// Où va la page qu'un choix du menu contextuel fait ouvrir.
nonisolated enum PageMenuDestination: Equatable, Sendable {
    /// Un onglet en arrière-plan, après l'onglet d'origine (comme ⌘-clic).
    case backgroundTab
    /// L'aperçu (Peek, tâche 4.4).
    case peek
}

/// Un élément de WebKit (par sa place dans le menu d'origine) et les éléments de Matcha qui le remplacent, dans
/// l'ordre. Chacun d'eux déclenche l'élément de WebKit remplacé.
nonisolated struct PageMenuReplacement: Equatable, Sendable {
    let index: Int
    let items: [PageMenuItem]
}

/// Réécriture du menu contextuel des pages, sans dépendance à l'interface : seuls les identifiants comptent.
nonisolated enum PageMenuPlan {
    /// Remplacements à faire dans un menu dont les éléments ont ces identifiants (nil : sans identifiant), dans
    /// l'ordre du menu. Un identifiant absent : rien ne change pour lui. Seule sa première occurrence compte.
    /// `offersPeek` : « Ouvrir dans un aperçu » a un sens ici (onglet de la barre, ni aperçu ni autre fenêtre).
    static func replacements(for identifiers: [String?], offersPeek: Bool) -> [PageMenuReplacement] {
        WebKitMenuItem.allCases.compactMap { original in
            identifiers.firstIndex(of: original.rawValue).map { index in
                PageMenuReplacement(index: index, items: items(replacing: original, offersPeek: offersPeek))
            }
        }
        .sorted { $0.index < $1.index }
    }

    private static func items(replacing original: WebKitMenuItem, offersPeek: Bool) -> [PageMenuItem] {
        switch original {
        case .openLinkInNewWindow:
            offersPeek ? [.openLinkInNewTab, .openLinkInPeek] : [.openLinkInNewTab]
        case .openImageInNewWindow:
            [.openImageInNewTab]
        }
    }
}
