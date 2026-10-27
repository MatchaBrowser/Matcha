/// Menu commands whose shortcut the user can change (Settings > Shortcuts), with their default shortcut. The others
/// stay as they are: macOS's standard commands (Edit, Find, Window, Quit…), tabs and Spaces by number (⌘1…, ⌃1…), ⌃⇥.
/// Pure type.
nonisolated enum MenuShortcut: String, CaseIterable, Sendable {
    case newTab
    case newWindow
    case newPrivateWindow
    case newMiniWindow
    case openLocation
    case openFile
    case openInSpace
    case closeTab
    case closeWindow
    case saveAs
    case exportPDF
    case print
    case copyURL
    case reloadPage
    case reloadFromOrigin
    case stopLoading
    case actualSize
    case zoomIn
    case zoomOut
    case translatePage
    case toggleSidebar
    case toggleDownloads
    case newSpace
    case homepage
    case reopenClosedTab
    case back
    case forward
    case showAllHistory

    /// Menu of the command, in the menu bar's order.
    enum Menu: CaseIterable, Sendable {
        case file
        case edit
        case view
        case spaces
        case history
    }

    var menu: Menu {
        switch self {
        case .newTab, .newWindow, .newPrivateWindow, .newMiniWindow, .openLocation, .openFile, .openInSpace: .file
        case .closeTab, .closeWindow, .saveAs, .exportPDF, .print: .file
        case .copyURL:
            .edit
        case .reloadPage, .reloadFromOrigin, .stopLoading, .actualSize, .zoomIn, .zoomOut, .translatePage:
            .view
        case .toggleSidebar, .toggleDownloads:
            .view
        case .newSpace:
            .spaces
        case .homepage, .reopenClosedTab, .back, .forward, .showAllHistory:
            .history
        }
    }

    /// As in Safari when it has the same command; ⌥⌘N for the mini window, as in Arc.
    var defaultKey: ShortcutKey? {
        switch self {
        case .newTab: ShortcutKey("t")
        case .newWindow: ShortcutKey("n")
        case .newPrivateWindow: ShortcutKey("n", [.command, .shift])
        case .newMiniWindow: ShortcutKey("n", [.command, .option])
        case .openLocation: ShortcutKey("l")
        case .openFile: ShortcutKey("o")
        case .openInSpace: ShortcutKey("o", [.command, .shift])
        case .closeTab: ShortcutKey("w")
        case .closeWindow: ShortcutKey("w", [.command, .shift])
        case .saveAs: ShortcutKey("s")
        case .exportPDF: nil
        case .print: ShortcutKey("p")
        case .copyURL: ShortcutKey("c", [.command, .shift])
        case .reloadPage: ShortcutKey("r")
        case .reloadFromOrigin: ShortcutKey("r", [.command, .option])
        case .stopLoading: ShortcutKey(".")
        case .actualSize: ShortcutKey("0")
        case .zoomIn: ShortcutKey("+")
        case .zoomOut: ShortcutKey("-")
        case .translatePage: nil
        case .toggleSidebar: ShortcutKey("s", [.command, .control])
        case .toggleDownloads: ShortcutKey("l", [.command, .option])
        case .newSpace: nil
        case .homepage: ShortcutKey("h", [.command, .shift])
        case .reopenClosedTab: ShortcutKey("t", [.command, .shift])
        case .back: ShortcutKey("[")
        case .forward: ShortcutKey("]")
        case .showAllHistory: ShortcutKey("y")
        }
    }

    /// Shortcuts that no command of this list can take: macOS's standard commands (with their ⌥ variants: Paste and
    /// Match Style, Close All, Minimize All, Quit and Keep Windows, review IU12), find and spelling, tabs and Spaces
    /// by number, the tab cycle, ⌘= (another name for ⌘+).
    static let fixedKeys: Set<ShortcutKey> = {
        var keys: Set<ShortcutKey> = [
            ShortcutKey("z"), ShortcutKey("z", [.command, .shift]), ShortcutKey("x"), ShortcutKey("c"), ShortcutKey("v"),
            ShortcutKey("v", [.command, .option, .shift]), ShortcutKey("w", [.command, .option]),
            ShortcutKey("m", [.command, .option]), ShortcutKey("q", [.command, .option]),
            ShortcutKey("a"), ShortcutKey("f"), ShortcutKey("f", [.command, .option]), ShortcutKey("g"),
            ShortcutKey("g", [.command, .shift]), ShortcutKey("e"), ShortcutKey("j"), ShortcutKey(":"), ShortcutKey(";"),
            ShortcutKey(","), ShortcutKey("q"), ShortcutKey("h"), ShortcutKey("h", [.command, .option]), ShortcutKey("m"),
            ShortcutKey("?"), ShortcutKey("f", [.command, .control]), ShortcutKey("="), ShortcutKey("`"),
            ShortcutKey(.space, [.command, .control]), ShortcutKey(.tab, .control), ShortcutKey(.tab, [.control, .shift]),
        ]
        for digit in "123456789" {
            keys.insert(ShortcutKey(digit))
            keys.insert(ShortcutKey(digit, .control))
        }
        return keys
    }()
}
