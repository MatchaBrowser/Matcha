import AppKit
import OSLog
import WebKit

/// Edit > Find, macOS's standard commands (audit H1), on the page of the active window (`FrontPage`): Find… (⌘F),
/// Find Next (⌘G), Find Previous (⇧⌘G), Use Selection for Find (⌘E), Jump to Selection (⌘J). The app delegate receives
/// them when no view before it does: a page doesn't, nor a text field (its editor only searches with a find bar of
/// its own), so they work from the command bar and from the find field too. “Find and Replace…” stays disabled.
/// One for the app (`AppEnvironment`); the browser windows register with it (`PageFindWindowModifier`).
@MainActor
final class PageFindResponder {
    /// A browser window: its front page, and the closing of its command bar (one text entry at a time).
    struct Window {
        weak var window: NSWindow?
        let page: () -> BrowserTab?
        let closeCommandBar: () -> Void
    }

    private var windows: [ObjectIdentifier: Window] = [:]
    /// The app's mini windows: the active one's page comes first.
    weak var miniWindows: MiniWindowManager?

    func register(_ window: Window) {
        windows = windows.filter { $0.value.window != nil }
        if let nsWindow = window.window {
            windows[ObjectIdentifier(nsWindow)] = window
        }
    }

    func unregister(_ window: NSWindow?) {
        windows = windows.filter { $0.value.window != nil && $0.value.window !== window }
    }

    // MARK: Commands

    func canPerform(tag: Int) -> Bool {
        target().map { Self.canPerform(tag: tag, hasQuery: $0.page.find.hasQuery) } ?? false
    }

    /// Find, and Use Selection for Find, always; Find Next and Find Previous once something was searched.
    nonisolated static func canPerform(tag: Int, hasQuery: Bool) -> Bool {
        switch NSFindPanelAction(rawValue: UInt(max(tag, 0))) {
        case .showFindPanel?, .setFindString?:
            true
        case .next?, .previous?:
            hasQuery
        default:
            false
        }
    }

    func perform(tag: Int) {
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

    var hasPage: Bool {
        target() != nil
    }

    /// ⌘J: the page scrolls to its selected text. Run in an isolated world, where the page can't redefine
    /// `getSelection` or `scrollIntoView` (review WB13).
    func jumpToSelection() {
        let script = """
        (() => {
            const selection = getSelection();
            if (selection.rangeCount) selection.getRangeAt(0).startContainer.parentElement?.scrollIntoView({block: 'center'});
        })()
        """
        target()?.page.webView?.evaluateJavaScript(script, in: nil, in: .defaultClient)
    }

    // MARK: Target

    /// The active mini window's page, otherwise the front page of the active browser window.
    private func target() -> (page: BrowserTab, closeCommandBar: () -> Void)? {
        if let mini = miniWindows?.keyWindow {
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
    private func useSelection(of page: BrowserTab) {
        guard let webView = page.webView else {
            return
        }
        Task {
            if let text = await Self.selectedText(in: webView) {
                page.find.useSelection(text)
            }
        }
    }

    /// The text selected in the page, read in an isolated world: the page can't redefine `getSelection` there and
    /// hand another text to the search (review WB13).
    static func selectedText(in webView: WKWebView) async -> String? {
        do {
            return try await webView.evaluateJavaScript("getSelection().toString()", contentWorld: .defaultClient) as? String
        } catch {
            Logger.browser.error("Unreadable page selection: \(error.logSummary, privacy: .public)")
            return nil
        }
    }
}
