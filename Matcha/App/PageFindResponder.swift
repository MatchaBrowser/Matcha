import AppKit
import OSLog
import WebKit

/// Edit > Find, macOS's standard commands (audit H1), on the page of the active window (`FrontPage`): Find… (⌘F),
/// Find Next (⌘G), Find Previous (⇧⌘G), Use Selection for Find (⌘E), Jump to Selection (⌘J). The app delegate receives
/// them when no view before it does: a page doesn't, nor a text field (its editor only searches with a find bar of
/// its own), so they work from the command bar and from the find field too. “Find and Replace…” stays disabled.
@MainActor
enum PageFindResponder {
    /// A browser window: its front page, and the closing of its command bar (one text entry at a time).
    struct Window {
        weak var window: NSWindow?
        let page: () -> BrowserTab?
        let closeCommandBar: () -> Void
    }

    private static var windows: [ObjectIdentifier: Window] = [:]

    static func register(_ window: Window) {
        windows = windows.filter { $0.value.window != nil }
        if let nsWindow = window.window {
            windows[ObjectIdentifier(nsWindow)] = window
        }
    }

    static func unregister(_ window: NSWindow?) {
        windows = windows.filter { $0.value.window != nil && $0.value.window !== window }
    }

    // MARK: Commands

    static func canPerform(tag: Int) -> Bool {
        guard let target = target() else {
            return false
        }
        switch NSFindPanelAction(rawValue: UInt(max(tag, 0))) {
        case .showFindPanel?, .setFindString?:
            return true
        case .next?, .previous?:
            return target.page.find.hasQuery
        default:
            return false
        }
    }

    static func perform(tag: Int) {
        guard let target = target() else {
            return
        }
        let find = target.page.find
        switch NSFindPanelAction(rawValue: UInt(max(tag, 0))) {
        case .showFindPanel?:
            // The command bar closes first: then the find bar opens, or stays open, and its field takes keyboard focus.
            target.closeCommandBar()
            find.present()
        case .next?:
            find.findNext()
        case .previous?:
            find.findPrevious()
        case .setFindString?:
            useSelection(of: target.page)
        default:
            break
        }
    }

    static var hasPage: Bool {
        target() != nil
    }

    /// ⌘J: the page scrolls to its selected text.
    static func jumpToSelection() {
        let script = """
        (() => {
            const selection = getSelection();
            if (selection.rangeCount) selection.getRangeAt(0).startContainer.parentElement?.scrollIntoView({block: 'center'});
        })()
        """
        target()?.page.webView?.evaluateJavaScript(script)
    }

    // MARK: Target

    /// The active mini window's page, otherwise the front page of the active browser window.
    private static func target() -> (page: BrowserTab, closeCommandBar: () -> Void)? {
        if let mini = ExtensionManager.shared.windows.miniWindows?.keyWindow {
            guard let page = FrontPage.page(miniWindowTab: mini.tab, tabManager: nil) else {
                return nil
            }
            return (page, {
                if mini.commandBar.isPresented {
                    mini.cancelCommandBar()
                }
            })
        }
        guard let keyWindow = NSApp.keyWindow, let window = windows[ObjectIdentifier(keyWindow)], let page = window.page() else {
            return nil
        }
        return (page, window.closeCommandBar)
    }

    /// ⌘E: the selected text of the page becomes the searched text (never logged).
    private static func useSelection(of page: BrowserTab) {
        page.webView?.evaluateJavaScript("getSelection().toString()") { result, error in
            if let error {
                Logger.browser.error("Unreadable page selection: \(error.logSummary, privacy: .public)")
            }
            if let text = result as? String {
                page.find.useSelection(text)
            }
        }
    }
}
