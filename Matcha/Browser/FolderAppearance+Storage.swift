import Foundation

/// Forme enregistrée de l'apparence d'un dossier (`FolderRecord`, et champs `icon`, `textColor`, `backgroundColor`
/// de la synchro, `SYNC.md`) : du texte court, lisible et tolérant (ce qui est illisible redevient la valeur par défaut).
nonisolated extension FolderAppearance {
    init(storedIcon: String?, textColorHex: String?, backgroundColorHex: String?) {
        self.init(
            icon: FolderIcon(storedValue: storedIcon),
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

nonisolated extension FolderIcon {
    private static let symbolPrefix = "symbol:"
    private static let emojiPrefix = "emoji:"

    /// « symbol:<nom du symbole SF> », « emoji:<emoji> », nil pour l'icône par défaut.
    var storedValue: String? {
        switch self {
        case .default: nil
        case let .symbol(name): Self.symbolPrefix + name
        case let .emoji(emoji): Self.emojiPrefix + emoji
        }
    }

    /// Icône lue dans sa forme enregistrée ; absente, inconnue ou invalide : l'icône par défaut.
    init(storedValue: String?) {
        guard let storedValue else {
            self = .default
            return
        }
        if storedValue.hasPrefix(Self.symbolPrefix) {
            let name = String(storedValue.dropFirst(Self.symbolPrefix.count))
            self = Self.isSymbolName(name) ? .symbol(name) : .default
        } else if storedValue.hasPrefix(Self.emojiPrefix) {
            self = FolderEmoji.validated(String(storedValue.dropFirst(Self.emojiPrefix.count))).map(FolderIcon.emoji) ?? .default
        } else {
            self = .default
        }
    }

    /// Nom de symbole SF plausible : lettres minuscules ASCII, chiffres et points. Un nom inconnu du système (synchro
    /// depuis un macOS plus récent) reste enregistré ; la barre affiche alors l'icône par défaut (`FolderIconView`).
    static func isSymbolName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") }
    }
}
