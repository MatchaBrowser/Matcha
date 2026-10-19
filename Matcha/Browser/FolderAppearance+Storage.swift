import Foundation

/// Stored form of a folder's appearance (`FolderRecord`, and the `icon`, `textColor`, `backgroundColor` fields of
/// sync, `SYNC.md`): short, readable and tolerant text (anything unreadable falls back to the default value).
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

    /// Summary readable by the UI tests (accessibility value of the row, in Debug):
    /// “symbol:star text:#FF3B30 background:none”.
    var summary: String {
        [
            storedIcon ?? "default",
            "text:" + (storedTextColor ?? "none"),
            "background:" + (storedBackgroundColor ?? "none"),
        ].joined(separator: " ")
    }
}
