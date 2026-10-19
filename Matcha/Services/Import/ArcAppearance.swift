import Foundation

/// Appearance of an Arc Space in Matcha (task 7.1): its icon and its theme. Pure type.
nonisolated enum ArcAppearance {
    /// Arc icons whose name differs from the closest SF symbol.
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

    /// Arc icons without a close SF symbol, rendered with an emoji.
    static let emojiNames: [String: String] = [
        "skull": "💀",
        "ghost": "👻",
        "alien": "👽",
        "robot": "🤖",
        "rocket": "🚀",
    ]

    /// Stored icon (`SidebarIcon.spaceSymbol`): the emoji, or the first existing SF symbol among the known name, the
    /// filled variant of Arc's name (like the Spaces' icons) and that name, otherwise the known emoji; nil if there is
    /// none (the Space keeps its default icon).
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

    /// Theme of the Space: Arc's colors (a single color gives a gradient towards a darker shade); nil without a color
    /// (the Space keeps its default theme).
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
