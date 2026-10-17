import Foundation

/// Textes et symboles des actions de la barre de commande.
nonisolated extension CommandActionID {
    /// Titre affiché, traduit.
    var title: String {
        switch self {
        case .newSpace: String(localized: "New Space")
        case .copyURL: String(localized: "Copy URL", comment: "Edit menu (⇧⌘C) and command bar action")
        case .settings: String(localized: "Settings", comment: "Command bar action")
        }
    }

    /// Mots cherchés en plus du titre, jamais affichés : ceux de la langue de l'app, puis les mots
    /// anglais, gardés par chaque traduction.
    var keywords: [String] {
        keywordList.split(separator: " ").map(String.init)
    }

    /// Symbole SF de la ligne.
    var symbolName: String {
        switch self {
        case .newSpace: "rectangle.stack.badge.plus"
        case .copyURL: "link"
        case .settings: "gearshape"
        }
    }

    private var keywordList: String {
        switch self {
        case .newSpace:
            String(
                localized: "commandBar.keywords.newSpace",
                defaultValue: "new create add space",
                comment: "Search words for the “New Space” action, space-separated, never displayed; keep the English words",
            )
        case .copyURL:
            String(
                localized: "commandBar.keywords.copyURL",
                defaultValue: "copy link address url",
                comment: "Search words for the “Copy URL” action, space-separated, never displayed; keep the English words",
            )
        case .settings:
            String(
                localized: "commandBar.keywords.settings",
                defaultValue: "settings preferences options",
                comment: "Search words for the “Settings” action, space-separated, never displayed; keep the English words",
            )
        }
    }
}
