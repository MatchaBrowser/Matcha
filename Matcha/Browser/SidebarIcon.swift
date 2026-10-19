import Foundation

/// Icon chosen for an item of the sidebar, folder of pinned tabs or Space: the item's default icon (the folder; the
/// circle for a Space), an SF Symbol or an emoji.
nonisolated enum SidebarIcon: Hashable, Sendable {
    case `default`
    /// Name of an SF Symbol (“star”…).
    case symbol(String)
    /// A single emoji, one character (`IconEmoji`).
    case emoji(String)

    /// Symbol of a folder's default icon, first in its grid.
    static let defaultFolderSymbol = "folder"
    /// Symbol of a Space's default icon, for an unreadable value; it is also the default value of
    /// `SpaceRecord.symbol`.
    static let defaultSpaceSymbol = "circle.fill"

    /// What the sidebar draws: the emoji, the symbol if this macOS knows it (`symbolExists`), otherwise
    /// `defaultSymbol` (default icon, or symbol received through sync from a more recent Mac). Never `.default`.
    func displayed(defaultSymbol: String, symbolExists: (String) -> Bool) -> SidebarIcon {
        switch self {
        case .emoji: self
        case let .symbol(name) where symbolExists(name): self
        case .default, .symbol: .symbol(defaultSymbol)
        }
    }

    /// Symbol circled in an icon grid (`SymbolPickerGrid`): its own, `defaultSymbol` for the default icon, nil for an
    /// emoji.
    func selectedSymbol(defaultSymbol: String) -> String? {
        switch self {
        case .default: defaultSymbol
        case let .symbol(name): name
        case .emoji: nil
        }
    }

    /// The icon's emoji, nil if it is not one.
    var emoji: String? {
        if case let .emoji(emoji) = self {
            return emoji
        }
        return nil
    }
}
