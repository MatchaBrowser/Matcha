import Foundation
import WebKit

/// Sign-in window pages as seen by the navigation delegate (`NavigationCoordinator`):
/// - site permissions and history: those of the originating page (its profile; nothing in a private window);
/// - downloads: in the session's list; a window that displayed nothing before downloading closes;
/// - ⌘-click, middle click, `target=_blank`, `window.open` without size, “… in New Tab” from the context menu
///   (task 5.9): as from the originating page (a tab of its window, or a mini window), as long as it is open;
///   otherwise another sign-in window, from the same profile;
/// - `window.open` with a size: another sign-in window, above this one (`NavigationCoordinator`);
/// - no peek: a Shift-click stays a click (`NavigationSource.other`), no “Open Link in Peek”;
/// - `window.close()`: the window closes;
/// - page process stopped (task 5.7): the page is visible as long as its window is open, it reloads.
extension PopupWindowManager: TabHost {
    func page(for webView: WKWebView) -> BrowserTab? {
        window(for: webView)?.tab
    }

    func navigationSource(of _: WKWebView) -> NavigationSource {
        .other
    }

    func isFavoriteOrPinned(_: WKWebView) -> Bool {
        false
    }

    func openLink(_ url: URL, configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) {
        guard let controller = window(for: webView) else {
            return
        }
        if let source = controller.opener.liveSource {
            source.host.openLink(url, configuration: configuration, from: source.webView, inBackground: inBackground)
            return
        }
        let tab = BrowserTab(configuration: configuration, openerID: controller.tab.id)
        show(tab, features: PopupWindowFeatures(), opener: PopupOpener(host: self, webView: webView)).tab.load(url, from: webView.url)
    }

    func openWindow(configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) -> WKWebView? {
        guard let controller = window(for: webView) else {
            return nil
        }
        if let source = controller.opener.liveSource {
            return source.host.openWindow(configuration: configuration, from: source.webView, inBackground: inBackground)
        }
        return open(configuration: configuration, features: PopupWindowFeatures(), opener: PopupOpener(host: self, webView: webView))
    }

    /// No peek in a sign-in window: refused, the link proceeds in place.
    func openInPeek(_: URL, from _: WKWebView, openingPoint _: CGPoint) -> Bool {
        false
    }

    func closePage(of webView: WKWebView) {
        window(for: webView)?.close()
    }

    /// A window that only downloads (no page displayed before) would stay empty: it closes, as in Safari, on the
    /// next turn of the main run loop (WebKit first finishes notifying the delegate). The download continues: it
    /// outlives the web view that started it (verified in 5.6, and by the tests).
    func downloadDidStart(in webView: WKWebView) {
        guard let controller = window(for: webView), webView.backForwardList.currentItem == nil else {
            return
        }
        Task { [weak controller] in
            controller?.close()
        }
    }

    func sitePermissions(for webView: WKWebView) -> SitePermissionScope? {
        window(for: webView)?.opener.sitePermissions
    }

    func historyScope(for webView: WKWebView) -> HistoryScope? {
        window(for: webView)?.opener.history
    }

    /// Window open, even in the background (like a mini window).
    func isVisible(_ page: BrowserTab) -> Bool {
        window(for: page) != nil
    }

    /// A sign-in window that opens another one giving its size: one more, above it.
    var popupWindows: (any PopupWindowHosting)? {
        self
    }
}
