import Foundation

/// Apparence d'un Space d'Arc dans Matcha (tâche 7.1) : son icône et son thème. Type pur.
nonisolated enum ArcAppearance {
    /// Icônes d'Arc dont le nom diffère du symbole SF le plus proche.
    static let symbolNames: [String: String] = [
        "grid": "square.grid.2x2.fill",
        "server": "server.rack",
        "code": "chevron.left.forwardslash.chevron.right",
        "music": "music.note",
        "game": "gamecontroller.fill",
        "school": "graduationcap.fill",
        "work": "briefcase.fill",
        "home": "house.fill",
        "travel": "airplane",
        "shopping": "cart.fill",
        "money": "dollarsign.circle.fill",
        "chat": "bubble.left.fill",
        "mail": "envelope.fill",
        "news": "newspaper.fill",
        "camera": "camera.fill",
        "video": "play.rectangle.fill",
        "planet": "globe.americas.fill",
    ]

    /// Icônes d'Arc sans symbole SF proche, rendues par un emoji.
    static let emojiNames: [String: String] = [
        "skull": "💀",
        "ghost": "👻",
        "alien": "👽",
        "robot": "🤖",
        "rocket": "🚀",
    ]

    /// Icône enregistrée (`SidebarIcon.spaceSymbol`) : l'emoji, ou le premier symbole SF existant parmi le nom
    /// connu, la variante pleine du nom d'Arc (comme les icônes des Spaces) et ce nom, sinon l'emoji connu ; nil s'il n'y en a pas (le
    /// Space garde l'icône
    /// donnée par défaut).
    static func spaceSymbol(for icon: ArcSidebar.Icon?, symbolExists: (String) -> Bool) -> String? {
        switch icon {
        case let .emoji(emoji):
            return SidebarIcon.emoji(emoji).spaceSymbol
        case let .named(name):
            let candidates = [symbolNames[name], "\(name).fill", name].compactMap(\.self)
            return candidates.first(where: symbolExists) ?? emojiNames[name].map { SidebarIcon.emoji($0).spaceSymbol }
        case nil:
            return nil
        }
    }

    /// Thème du Space : les couleurs d'Arc (une seule couleur donne un dégradé vers une teinte plus sombre) ; nil sans
    /// couleur (le Space garde le thème donné par défaut).
    static func theme(for colors: [ThemeColor]) -> SpaceTheme? {
        switch colors.count {
        case 0:
            nil
        case 1:
            SpaceTheme(colors: [colors[0], colors[0].mixed(with: .black, amount: 0.35)])
        default:
            SpaceTheme(colors: Array(colors.prefix(3)))
        }
    }
}
