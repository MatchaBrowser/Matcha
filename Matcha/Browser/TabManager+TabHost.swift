import Foundation
import WebKit

/// The pages of a Space as seen by the navigation delegate: placed tabs and Peek (task 4.4).
extension TabManager: TabHost {
    func page(for webView: WKWebView) -> BrowserTab? {
        tabOrPeek(for: webView)
    }

    func navigationSource(of webView: WKWebView) -> NavigationSource {
        if isPeek(webView) {
            return .peek
        }
        return tab(for: webView) == nil ? .other : .tab
    }

    func isFavoriteOrPinned(_ webView: WKWebView) -> Bool {
        guard let tab = tab(for: webView), let place = place(of: tab) else {
            return false
        }
        return place != .today
    }

    /// After the source tab; from the Peek, after its source tab.
    func openLink(_ url: URL, configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) {
        insertTab(configuration: configuration, after: insertionAnchor(for: webView), select: !inBackground).load(url)
    }

    /// Window without a size opened by the Peek: the Peek first becomes a tab, so that `window.opener` stays valid.
    /// A sign-in window (size given, task 5.8) goes into its own window and the Peek stays a Peek
    /// (`NavigationCoordinator`). In the background (context menu, task 5.9): after the source tab, or the Peek's,
    /// which stays a Peek.
    func openWindow(configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) -> WKWebView? {
        if inBackground {
            return insertTab(configuration: configuration, after: insertionAnchor(for: webView), select: false).makeWebViewIfNeeded()
        }
        let opener = tab(for: webView) ?? (isPeek(webView) ? openPeekAsTab() : nil)
        return insertTab(configuration: configuration, after: opener, select: true).makeWebViewIfNeeded()
    }

    /// Refused if the source web view is not displayed.
    func openInPeek(_ url: URL, from webView: WKWebView, openingPoint: CGPoint) -> Bool {
        guard let source = tabOrPeek(for: webView), canPeek(from: source) else {
            return false
        }
        openPeek(url, from: source, openingPoint: openingPoint)
        return true
    }

    /// Tabs and Peek share the Space's profile.
    func sitePermissions(for _: WKWebView) -> SitePermissionScope? {
        sitePermissions
    }

    /// Tabs and Peek: the profile and the Space of this Space.
    func historyScope(for _: WKWebView) -> HistoryScope? {
        history
    }

    /// The Peek is visible: it only opens on top of a displayed page and closes with it. A tab is visible if it is
    /// displayed in an open window (selected or pane of its split, in the displayed Space: notion from task 5.6);
    /// without this tracking (tests), if it is displayed by this Space.
    func isVisible(_ page: BrowserTab) -> Bool {
        if peek?.tab === page {
            return true
        }
        guard tab(withID: page.id) === page else {
            return false
        }
        return lifecycle?.isVisible(page) ?? displayedTabIDs.contains(page.id)
    }

    func closePage(of webView: WKWebView) {
        if isPeek(webView) {
            PeekActions.close(in: self)
        } else if let tab = tab(for: webView) {
            close(tab)
        }
    }
}
