import Foundation
import WebKit

/// What the navigation delegate (`NavigationCoordinator`) asks of whoever owns the pages: the tabs of a Space and their
/// Peek (`TabManager`), the mini windows (`MiniWindowManager`, task 4.5) or the sign-in windows (`PopupWindowManager`,
/// task 5.8). A single delegate for all pages: tasks 5.5 (history) and 5.8 (sign-in windows) apply to all of them.
@MainActor
protocol TabHost: AnyObject {
    var faviconService: FaviconService { get }
    /// Window the downloads of these pages go back to (task 5.1).
    var downloadScope: DownloadScope { get }
    /// Tab, or page outside the sidebar (Peek, mini window), that owns `webView`.
    func page(for webView: WKWebView) -> BrowserTab?
    /// Web view a navigation starts from, for `NavigationPolicy`.
    func navigationSource(of webView: WKWebView) -> NavigationSource
    /// True if `webView` belongs to a favorite or a pinned tab (links to other sites in Peek).
    func isFavoriteOrPinned(_ webView: WKWebView) -> Bool
    /// ⌘-click, middle click: `url` in a tab; `configuration` is that of the originating view (same profile).
    func openLink(_ url: URL, configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool)
    /// `target=_blank`, `window.open` without a size: a view created with `configuration` as is, otherwise
    /// `window.opener` does not work; nil refuses the window. With a size, `popupWindows` receives it.
    /// `inBackground`: “Open … in New Tab” from the context menu (task 5.9), a background tab placed like that of a
    /// ⌘-click (`openLink`).
    func openWindow(configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) -> WKWebView?
    /// Sign-in windows of the session (task 5.8): a page that opens a window giving its size gets it in its own small
    /// window; nil (tests): a tab, as without a size.
    var popupWindows: PopupWindowManager? { get }
    /// Shift-click: `url` in Peek; false if it is refused (the link then proceeds as usual).
    func openInPeek(_ url: URL, from webView: WKWebView, openingPoint: CGPoint) -> Bool
    /// The page called `window.close()`.
    func closePage(of webView: WKWebView)
    /// Permission decisions of the profile of `webView` (task 5.2); nil: nothing is remembered.
    func sitePermissions(for webView: WKWebView) -> SitePermissionScope?
    /// Per-site page zoom (task 5.4); nil: pages keep their zoom from one page to the next.
    var siteZooms: SiteZoomStore? { get }
    /// Blocker of the session (task 6.2); nil (tests): the pages are not followed by the blocker.
    var contentBlocking: ContentBlockerScope? { get }
    /// History where the visits of `webView` are recorded (task 5.5); nil: nothing is recorded (private window).
    func historyScope(for webView: WKWebView) -> HistoryScope?
    /// True if `page` is on screen (task 5.7): a page whose process stops reloads right away if it is visible,
    /// otherwise when it is shown.
    func isVisible(_ page: BrowserTab) -> Bool
    /// A navigation of `webView` has just become a download (task 5.1), already handed to the list.
    func downloadDidStart(in webView: WKWebView)
}

extension TabHost {
    /// Nothing by default: a tab opened for a download stays open (`FEATURES.md`).
    func downloadDidStart(in _: WKWebView) {}

    /// No blocker by default (test hosts).
    var contentBlocking: ContentBlockerScope? {
        nil
    }
}
