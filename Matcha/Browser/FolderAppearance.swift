import Foundation

/// Appearance of a folder of pinned tabs, chosen in its customization panel: icon, text color and background color
/// (nil: the system ones). The colors are displayed as is, in light as in dark mode.
nonisolated struct FolderAppearance: Hashable, Sendable {
    var icon = SidebarIcon.default
    var textColor: ThemeColor?
    var backgroundColor: ThemeColor?

    static let `default` = FolderAppearance()

    var isDefault: Bool {
        self == .default
    }

    /// Color of the name and symbol: the chosen one; otherwise, on a chosen background, black or white, whichever is
    /// more readable on that background; otherwise nil (system text color).
    var displayedTextColor: ThemeColor? {
        textColor ?? backgroundColor?.readableTextColor
    }

    /// The same appearance as it will be stored and read back: colors reduced to 8 bits per component (`#RRGGBB`),
    /// emoji and symbol name checked (invalid: the default icon). An arrangement held in memory this way is identical
    /// after a round trip through the database.
    var normalized: FolderAppearance {
        FolderAppearance(storedIcon: storedIcon, textColorHex: storedTextColor, backgroundColorHex: storedBackgroundColor)
    }
}
