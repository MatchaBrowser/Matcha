import AppKit
import Foundation
import WebKit

/// Closing the peek, opening it as a tab; keyboard focus follows.
@MainActor
enum PeekActions {
    /// Help tag and label of the ×, File menu item in place of “Close Tab” (⌘W).
    static let closeTitle = LocalizedStringResource(
        "Close Peek",
        comment: "Peek: help tag and accessibility label of the × button; File menu item replacing “Close Tab” (⌘W) while a peek is open",
    )

    /// ⎋, ⌘W, ×, click beside it, `window.close()`: the peek closes, the originating page takes keyboard focus back.
    static func close(in tabManager: TabManager) {
        guard let peek = tabManager.peek else {
            return
        }
        let source = tabManager.tab(withID: peek.sourceTabID) ?? tabManager.selectedTab
        releaseKeyboard(from: peek.tab.webView)
        tabManager.closePeek()
        if let source {
            TabActivation.focusPage(of: source)
        }
    }

    /// “Open as Tab”: the page moves into the card, then takes back the keyboard focus lost during the move.
    /// The web view leaves the peek in the same update as it enters the card: it never has two parents (AppKit
    /// removes it from its container when the card adds it).
    static func openAsTab(in tabManager: TabManager) {
        guard let webView = tabManager.peek?.tab.webView else {
            return
        }
        let oldHost = webView.superview
        releaseKeyboard(from: webView)
        tabManager.openPeekAsTab()
        PeekFocus.focus(webView, awayFrom: oldHost)
    }

    /// Gives keyboard focus back to the window if it is in the peek's page (never taken from another field).
    private static func releaseKeyboard(from webView: WKWebView?) {
        guard let webView, let window = webView.window, let responder = window.firstResponder as? NSView else {
            return
        }
        if responder === webView || responder.isDescendant(of: webView) {
            window.makeFirstResponder(nil)
        }
    }
}
