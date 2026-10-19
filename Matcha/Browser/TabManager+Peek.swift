import Foundation
import OSLog
import WebKit

/// Peek (task 4.4): a page opened on top of the displayed pages, outside the sidebar. It is a `BrowserTab` that the
/// sidebar does not know; “Open as Tab” places this same object: same web view, same history, nothing is reloaded.
/// It is never saved.
/// Task 5.7: a crashed Peek page is visible (`isVisible`), so it reloads.
/// Task 6.3: for extensions, the open Peek is a tab, right after its source tab, and the active tab
/// (`ExtensionWindows`).
extension TabManager {
    /// Page in the foreground: the Peek if it is open, otherwise the selected tab, which is also the active pane
    /// of a split (⌘R, ⌘[, ⌘], ⇧⌘C; 5.3, 5.4).
    var frontTab: BrowserTab? {
        peek?.tab ?? selectedTab
    }

    func isPeek(_ webView: WKWebView) -> Bool {
        peek.map { $0.tab.webView === webView } ?? false
    }

    /// Placed tab, or Peek page, that owns `webView` (`tab(for:)` stays limited to placed tabs).
    func tabOrPeek(for webView: WKWebView) -> BrowserTab? {
        tab(for: webView) ?? (isPeek(webView) ? peek?.tab : nil)
    }

    /// Tab after which to place what `webView` opens: its own, or for the Peek, its source tab.
    /// Task 5.9: “Open Link in New Tab” from the Peek uses it, with `select: false`.
    func insertionAnchor(for webView: WKWebView) -> BrowserTab? {
        if let tab = tab(for: webView) {
            return tab
        }
        guard let peek, isPeek(webView) else {
            return nil
        }
        return tab(withID: peek.sourceTabID)
    }

    /// A Peek only opens on top of a displayed page (the selected tab or a pane of its split), or from the Peek
    /// itself, which loads the link.
    func canPeek(from source: BrowserTab) -> Bool {
        source === peek?.tab || displayedTabIDs.contains(source.id)
    }

    /// Opens `url` in a new Peek, with the configuration of `source` (same profile); a Peek already open is closed
    /// first, and a split pane becomes the active pane. From the Peek, `url` loads in it.
    /// Nil if `source` is not displayed. Entry point of the pages' context menu (task 5.9).
    @discardableResult
    func openPeek(_ url: URL, from source: BrowserTab, openingPoint: CGPoint = PeekLayout.center) -> Peek? {
        if let peek, source === peek.tab {
            peek.tab.load(url, from: peek.tab.url)
            return peek
        }
        guard canPeek(from: source) else {
            Logger.peek.notice("Aperçu refusé : l'onglet d'origine n'est pas affiché")
            return nil
        }
        closePeek()
        if source.id != selectedTabID {
            // Pane of a split (Shift+Return on a link): the Peek belongs to the active pane.
            setSelection(source.id)
        }
        let page = BrowserTab(configuration: source.configuration, openerID: source.id)
        page.delegate = coordinator
        page.load(url, from: source.url)
        let newPeek = Peek(tab: page, sourceTabID: source.id, openingPoint: openingPoint)
        setPeek(newPeek)
        Logger.peek.info("Aperçu ouvert")
        return newPeek
    }

    /// Closes the Peek: its web view is released (sound, process). Does not touch the keyboard (`PeekActions`).
    func closePeek() {
        guard let peek else {
            return
        }
        setPeek(nil)
        peek.tab.unload(resettingTo: nil, title: nil)
        Logger.peek.debug("Aperçu fermé")
    }

    /// “Open as Tab”: the Peek page becomes a today tab, on its own, after its source tab (and its split) and those
    /// already opened from it (at the top if it is pinned or a favorite), and selected.
    @discardableResult
    func openPeekAsTab() -> BrowserTab? {
        guard let peek else {
            return nil
        }
        setPeek(nil)
        insert(peek.tab, after: tab(withID: peek.sourceTabID), select: true)
        Logger.peek.info("Aperçu ouvert en onglet")
        return peek.tab
    }
}
