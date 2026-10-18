import Foundation

/// Forme enregistrée de l'apparence d'un dossier (`FolderRecord`, et champs `icon`, `textColor`, `backgroundColor`
/// de la synchro, `SYNC.md`) : du texte court, lisible et tolérant (ce qui est illisible redevient la valeur par défaut).
nonisolated extension FolderAppearance {
    init(storedIcon: String?, textColorHex: String?, backgroundColorHex: String?) {
        self.init(
            icon: SidebarIcon(storedValue: storedIcon),
            textColor: textColorHex.flatMap(ThemeColor.init(hexString:)),
            backgroundColor: backgroundColorHex.flatMap(ThemeColor.init(hexString:)),
        )
    }

    var storedIcon: String? {
        icon.storedValue
    }

    var storedTextColor: String? {
        textColor?.hexString
    }

    var storedBackgroundColor: String? {
        backgroundColor?.hexString
    }

    /// Résumé lisible par les tests d'interface (valeur d'accessibilité de la ligne, en Debug) :
    /// « symbol:star text:#FF3B30 background:none ».
    var summary: String {
        [
            storedIcon ?? "default",
            "text:" + (storedTextColor ?? "none"),
            "background:" + (storedBackgroundColor ?? "none"),
        ].joined(separator: " ")
    }
}
