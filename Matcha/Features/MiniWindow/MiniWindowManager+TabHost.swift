import Foundation
import OSLog
import WebKit

/// The mini windows' pages as seen by the navigation delegate (`NavigationCoordinator`):
/// - `target=_blank` and `window.open` without a size: a new mini window, created with the configuration provided
///   by WebKit (`window.opener` stays valid), same profile;
/// - `window.open` with a size (sign-in window, task 5.8): a small window above the mini window
///   (`PopupWindowManager` of the main session);
/// - ⌘-click, middle click, ⇧⌘-click, “… in New Tab” from the context menu (task 5.9): a background tab in the
///   target Space, the main window does not come to the front; without a Space of that profile, a new mini window
///   (never another profile's cookies);
/// - `window.close()`: the mini window closes;
/// - no Peek: a Shift-click stays a click (`NavigationSource.other`), no “Open Link in Peek”;
/// - downloads: in the main window's list;
/// - site permissions: decisions of the mini window's profile, banner in its page;
/// - history: visits kept for the mini window's profile, without a Space;
/// - page process terminated: the page is visible as long as its mini window is open, it reloads.
extension MiniWindowManager: TabHost {
    var faviconService: FaviconService {
        session.faviconService
    }

    /// Mini windows have no sidebar: their downloads go into the main window's list.
    var downloadScope: DownloadScope {
        .regular
    }

    func page(for webView: WKWebView) -> BrowserTab? {
        window(for: webView)?.tab
    }

    func navigationSource(of _: WKWebView) -> NavigationSource {
        .other
    }

    func isFavoriteOrPinned(_: WKWebView) -> Bool {
        false
    }

    func openLink(_ url: URL, configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground _: Bool) {
        let opener = window(for: webView)
        let profileID = opener?.profileID ?? displayedSpace.record.profile?.id
        let space = defaultTarget(profileID: profileID)
        guard space.record.profile?.id == profileID else {
            // No Space of this profile left: the page opens alongside, in a mini window of the same profile.
            let controller = show(BrowserTab(configuration: configuration, openerID: opener?.tab.id), profileID: profileID)
            controller.tab.load(url, from: webView.url)
            controller.showWebView()
            Logger.miniWindow.info("Mini-fenêtre ouverte (\(Source.link.rawValue, privacy: .public))")
            return
        }
        space.tabManager.newTab(url: url, select: false, from: webView.url)
        Logger.miniWindow.info("Lien d'une mini-fenêtre ouvert en arrière-plan dans un Space")
    }

    /// A new mini window. In the background (context menu, task 5.9): a background tab of the target Space, like
    /// ⌘-click; without a Space of that profile, a mini window all the same.
    func openWindow(configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) -> WKWebView? {
        let opener = window(for: webView)
        let profileID = opener?.profileID ?? displayedSpace.record.profile?.id
        if inBackground {
            let space = defaultTarget(profileID: profileID)
            if space.record.profile?.id == profileID {
                Logger.miniWindow.info("Lien d'une mini-fenêtre ouvert en arrière-plan dans un Space")
                return space.tabManager.insertTab(configuration: configuration, after: nil, select: false).makeWebViewIfNeeded()
            }
        }
        let controller = show(BrowserTab(configuration: configuration, openerID: opener?.tab.id), profileID: profileID)
        let newWebView = controller.tab.makeWebViewIfNeeded()
        controller.showWebView()
        Logger.miniWindow.info("Mini-fenêtre ouverte (\(Source.page.rawValue, privacy: .public))")
        return newWebView
    }

    /// No Peek in a mini window (never requested): refused, the link proceeds in place.
    func openInPeek(_: URL, from _: WKWebView, openingPoint _: CGPoint) -> Bool {
        false
    }

    func closePage(of webView: WKWebView) {
        window(for: webView)?.close()
    }

    /// Mini window open, even in the background (like a minimized window for sleeping, task 5.6).
    func isVisible(_ page: BrowserTab) -> Bool {
        window(for: page) != nil
    }

    /// Per-site zoom of the main session: a mini window is never private (task 5.4).
    var siteZooms: SiteZoomStore? {
        session.siteZooms
    }

    /// Sign-in windows of the main session (task 5.8).
    var popupWindows: PopupWindowManager? {
        session.popupWindows
    }

    /// Blocker of the main session (task 6.2): its saved exceptions.
    var contentBlocking: ContentBlockerScope? {
        session.contentBlocking
    }

    /// Decisions of the mini window's profile (never private: they are saved).
    func sitePermissions(for webView: WKWebView) -> SitePermissionScope? {
        window(for: webView).map { SitePermissionScope(store: session.sitePermissions, profileID: $0.profileID) }
    }

    /// History of the mini window's profile, without a Space (task 5.5).
    func historyScope(for webView: WKWebView) -> HistoryScope? {
        guard let store = session.history, let controller = window(for: webView) else {
            return nil
        }
        return HistoryScope(store: store, profileID: controller.profileID, spaceID: nil)
    }
}
