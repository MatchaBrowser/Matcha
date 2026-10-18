import Foundation

/// Apparence d'un dossier d'épinglés, choisie dans son panneau de personnalisation : icône, couleur du texte et
/// couleur du fond (nil : celles du système). Les couleurs s'affichent telles quelles, en clair comme en sombre.
nonisolated struct FolderAppearance: Hashable, Sendable {
    var icon = SidebarIcon.default
    var textColor: ThemeColor?
    var backgroundColor: ThemeColor?

    static let `default` = FolderAppearance()

    var isDefault: Bool {
        self == .default
    }

    /// Couleur du nom et du symbole : celle choisie ; sinon, sur un fond choisi, le noir ou le blanc, le plus lisible
    /// sur ce fond ; sinon nil (couleur du texte du système).
    var displayedTextColor: ThemeColor? {
        textColor ?? backgroundColor?.readableTextColor
    }

    /// La même apparence telle qu'elle sera enregistrée et relue : couleurs ramenées à 8 bits par composante
    /// (`#RRGGBB`), emoji et nom de symbole vérifiés (invalides : l'icône par défaut). Un rangement ainsi tenu
    /// en mémoire est identique après un aller-retour par la base.
    var normalized: FolderAppearance {
        FolderAppearance(storedIcon: storedIcon, textColorHex: storedTextColor, backgroundColorHex: storedBackgroundColor)
    }
}
