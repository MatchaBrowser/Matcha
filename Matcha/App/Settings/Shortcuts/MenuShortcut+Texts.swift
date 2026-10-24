import Foundation

extension MenuShortcut {
    /// Name in Settings > Shortcuts: the menu item's title (one title for the items that change, such as “Hide
    /// Sidebar”).
    var title: String {
        switch self {
        case .newTab: String(localized: "New Tab")
        case .newWindow: String(localized: "New Window")
        case .newPrivateWindow: String(localized: "New Private Window")
        case .newMiniWindow: String(localized: "New Mini Window")
        case .openLocation: String(localized: "Open Location…")
        case .openFile: String(localized: "Open File…")
        case .openInSpace: String(localized: "Open in Space")
        case .closeTab: String(localized: "Close Tab")
        case .closeWindow: String(localized: "Close Window")
        case .saveAs: String(localized: "Save As…", comment: "Context menu of a web page: saves it as a web archive or its source")
        case .exportPDF: String(localized: "Export as PDF…")
        case .print: String(localized: "Print…")
        case .copyURL: CommandActionID.copyURL.title
        case .reloadPage: String(localized: "Reload Page")
        case .reloadFromOrigin: String(localized: "Reload Page From Origin", comment: "View menu: reloads without the cache (⌥⌘R)")
        case .stopLoading: String(localized: "Stop", comment: "Toolbar button: stop loading the page")
        case .actualSize: String(localized: "Actual Size")
        case .zoomIn: String(localized: "Zoom In")
        case .zoomOut: String(localized: "Zoom Out")
        case .toggleSidebar: String(localized: "Show or Hide Sidebar", comment: "Settings > Shortcuts: the View menu item")
        case .toggleDownloads: String(localized: "Show or Hide Downloads", comment: "Settings > Shortcuts: the View menu item")
        case .newSpace: String(localized: "New Space")
        case .homepage: String(localized: "Homepage")
        case .reopenClosedTab: String(localized: "Reopen Closed Tab", comment: "History menu (⇧⌘T)")
        case .back: String(localized: "Back")
        case .forward: String(localized: "Forward")
        case .showAllHistory: String(localized: "Show All History")
        }
    }
}

extension MenuShortcut.Menu {
    var title: String {
        switch self {
        case .file: String(localized: "File", comment: "Settings > Shortcuts: commands of the File menu")
        case .edit: String(localized: "Edit", comment: "Settings > Shortcuts: commands of the Edit menu")
        case .view: String(localized: "View", comment: "Settings > Shortcuts: commands of the View menu")
        case .spaces: String(localized: "Spaces")
        case .history: String(localized: "History")
        }
    }
}

extension ShortcutProblem {
    var message: String {
        switch self {
        case .needsCommandOrControl:
            String(localized: "Use ⌘ or ⌃ in the shortcut.", comment: "Settings > Shortcuts: refused shortcut")
        case let .usedBy(command):
            String(localized: "Already used by “\(command.title)”.", comment: "Settings > Shortcuts: refused shortcut; a menu command")
        case .usedByMatcha:
            String(localized: "Matcha uses this shortcut for another command.", comment: "Settings > Shortcuts: refused shortcut")
        case .usedByMacOS:
            String(localized: "macOS uses this shortcut.", comment: "Settings > Shortcuts: refused shortcut")
        case .usedByMiniWindowShortcut:
            String(localized: "This shortcut opens a mini window from any app.", comment: "Settings > Shortcuts: refused shortcut")
        }
    }
}
