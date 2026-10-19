import Foundation

/// Texts and symbols of the command bar actions.
nonisolated extension CommandActionID {
    /// Displayed title, localized.
    var title: String {
        switch self {
        case .newSpace: String(localized: "New Space")
        case .copyURL: String(localized: "Copy URL", comment: "Edit menu (⇧⌘C) and command bar action")
        case .settings: String(localized: "Settings", comment: "Command bar action")
        }
    }

    /// Words searched in addition to the title, never displayed: those of the app's language, then the English
    /// words, kept by each translation.
    var keywords: [String] {
        keywordList.split(separator: " ").map(String.init)
    }

    /// SF Symbol of the row.
    var symbolName: String {
        switch self {
        case .newSpace: "rectangle.stack.badge.plus"
        case .copyURL: "link"
        case .settings: "gearshape"
        }
    }

    private var keywordList: String {
        switch self {
        case .newSpace:
            String(
                localized: "commandBar.keywords.newSpace",
                defaultValue: "new create add space",
                comment: "Search words for the “New Space” action, space-separated, never displayed; keep the English words",
            )
        case .copyURL:
            String(
                localized: "commandBar.keywords.copyURL",
                defaultValue: "copy link address url",
                comment: "Search words for the “Copy URL” action, space-separated, never displayed; keep the English words",
            )
        case .settings:
            String(
                localized: "commandBar.keywords.settings",
                defaultValue: "settings preferences options",
                comment: "Search words for the “Settings” action, space-separated, never displayed; keep the English words",
            )
        }
    }
}
