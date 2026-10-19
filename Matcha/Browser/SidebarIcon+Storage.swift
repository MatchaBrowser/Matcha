import Foundation

/// Stored forms of an icon: `FolderRecord.iconValue` and `SpaceRecord.symbol` (the `icon` field of a folder and the
/// `symbol` field of a Space in sync, `SYNC.md`). Short, readable and tolerant text: anything unreadable falls back to
/// the default icon.
nonisolated extension SidebarIcon {
    private static let symbolPrefix = "symbol:"
    private static let emojiPrefix = "emoji:"

    /// Form for a folder: “symbol:<SF Symbol name>”, “emoji:<emoji>”, nil for the default icon.
    var storedValue: String? {
        switch self {
        case .default: nil
        case let .symbol(name): Self.symbolPrefix + name
        case let .emoji(emoji): Self.emojiPrefix + emoji
        }
    }

    /// Icon read from a folder's form; missing, unknown or invalid: the default icon.
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

    /// Plausible SF Symbol name: lowercase ASCII letters, digits and dots. A name unknown to the system (synced from a
    /// more recent macOS) stays stored; the sidebar then displays the default icon (`displayed`).
    static func isSymbolName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") }
    }
}

// MARK: - Space

nonisolated extension SidebarIcon {
    /// Icon of a Space read from `SpaceRecord.symbol`: a bare symbol name (the form from before emoji, still written
    /// for a symbol), “emoji:<emoji>”, or “symbol:<name>” (a folder's form, also accepted). Never `.default`: an
    /// unreadable value gives the circle.
    init(spaceSymbol: String) {
        let icon = Self.isSymbolName(spaceSymbol) ? .symbol(spaceSymbol) : SidebarIcon(storedValue: spaceSymbol)
        self = icon == .default ? .symbol(Self.defaultSpaceSymbol) : icon
    }

    /// Form written to `SpaceRecord.symbol`: the bare name for a symbol (as before emoji), “emoji:<emoji>” for an
    /// emoji; the default icon is the circle.
    var spaceSymbol: String {
        switch self {
        case .default: Self.defaultSpaceSymbol
        case let .symbol(name): name
        case let .emoji(emoji): Self.emojiPrefix + emoji
        }
    }
}
