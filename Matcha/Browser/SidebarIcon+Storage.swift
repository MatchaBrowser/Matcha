import Foundation

/// Formes enregistrées d'une icône : `FolderRecord.iconValue` et `SpaceRecord.symbol` (champs `icon` d'un dossier et
/// `symbol` d'un Space dans la synchro, `SYNC.md`). Du texte court, lisible et tolérant : ce qui est illisible redevient
/// l'icône par défaut.
nonisolated extension SidebarIcon {
    private static let symbolPrefix = "symbol:"
    private static let emojiPrefix = "emoji:"

    /// Forme d'un dossier : « symbol:<nom du symbole SF> », « emoji:<emoji> », nil pour l'icône par défaut.
    var storedValue: String? {
        switch self {
        case .default: nil
        case let .symbol(name): Self.symbolPrefix + name
        case let .emoji(emoji): Self.emojiPrefix + emoji
        }
    }

    /// Icône lue dans la forme d'un dossier ; absente, inconnue ou invalide : l'icône par défaut.
    init(storedValue: String?) {
        guard let storedValue else {
            self = .default
            return
        }
        if storedValue.hasPrefix(Self.symbolPrefix) {
            let name = String(storedValue.dropFirst(Self.symbolPrefix.count))
            self = Self.isSymbolName(name) ? .symbol(name) : .default
        } else if storedValue.hasPrefix(Self.emojiPrefix) {
            self = IconEmoji.validated(String(storedValue.dropFirst(Self.emojiPrefix.count))).map(SidebarIcon.emoji) ?? .default
        } else {
            self = .default
        }
    }

    /// Nom de symbole SF plausible : lettres minuscules ASCII, chiffres et points. Un nom inconnu du système (synchro
    /// depuis un macOS plus récent) reste enregistré ; la barre affiche alors l'icône par défaut (`displayed`).
    static func isSymbolName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") }
    }
}

// MARK: - Space

nonisolated extension SidebarIcon {
    /// Icône d'un Space lue dans `SpaceRecord.symbol` : un nom de symbole seul (la forme d'avant les emoji, toujours
    /// écrite pour un symbole), « emoji:<emoji> », ou « symbol:<nom> » (forme d'un dossier, acceptée aussi). Jamais
    /// `.default` : une valeur illisible donne le cercle.
    init(spaceSymbol: String) {
        let icon = Self.isSymbolName(spaceSymbol) ? .symbol(spaceSymbol) : SidebarIcon(storedValue: spaceSymbol)
        self = icon == .default ? .symbol(Self.defaultSpaceSymbol) : icon
    }

    /// Forme écrite dans `SpaceRecord.symbol` : le nom seul pour un symbole (comme avant les emoji), « emoji:<emoji> »
    /// pour un emoji ; l'icône par défaut est le cercle.
    var spaceSymbol: String {
        switch self {
        case .default: Self.defaultSpaceSymbol
        case let .symbol(name): name
        case let .emoji(emoji): Self.emojiPrefix + emoji
        }
    }
}
