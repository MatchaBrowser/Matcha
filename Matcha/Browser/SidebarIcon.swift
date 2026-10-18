import Foundation

/// Icône choisie pour un élément de la barre latérale, dossier d'épinglés ou Space : l'icône par défaut de l'élément
/// (le dossier ; le cercle pour un Space), un symbole SF ou un emoji.
nonisolated enum SidebarIcon: Hashable, Sendable {
    case `default`
    /// Nom d'un symbole SF (« star »…).
    case symbol(String)
    /// Un seul emoji, un caractère (`IconEmoji`).
    case emoji(String)

    /// Symbole de l'icône par défaut d'un dossier, premier de sa grille.
    static let defaultFolderSymbol = "folder"
    /// Symbole de l'icône par défaut d'un Space, pour une valeur illisible ; c'est aussi la valeur par défaut de
    /// `SpaceRecord.symbol`.
    static let defaultSpaceSymbol = "circle.fill"

    /// Ce que la barre dessine : l'emoji, le symbole si ce macOS le connaît (`symbolExists`), sinon `defaultSymbol`
    /// (icône par défaut, ou symbole reçu par la synchro d'un Mac plus récent). Jamais `.default`.
    func displayed(defaultSymbol: String, symbolExists: (String) -> Bool) -> SidebarIcon {
        switch self {
        case .emoji: self
        case let .symbol(name) where symbolExists(name): self
        case .default, .symbol: .symbol(defaultSymbol)
        }
    }

    /// Symbole entouré dans une grille d'icônes (`SymbolPickerGrid`) : le sien, `defaultSymbol` pour l'icône par
    /// défaut, nil pour un emoji.
    func selectedSymbol(defaultSymbol: String) -> String? {
        switch self {
        case .default: defaultSymbol
        case let .symbol(name): name
        case .emoji: nil
        }
    }

    /// L'emoji de l'icône, nil si elle n'en est pas un.
    var emoji: String? {
        if case let .emoji(emoji) = self {
            return emoji
        }
        return nil
    }
}
