import AppKit
import OSLog
import WebKit

/// Sign-in windows of a session (task 5.8): a page that opens a window giving its size
/// (`window.open(url, name, "width=500,height=600")`: Google or Apple sign-in, bank, payment) gets it in its own
/// small window, above its originating window, instead of a tab; from a peek, the peek stays a peek; from a mini
/// window, likewise. One instance per session (`BrowserSession.popupWindows`): those of a private window are
/// private and close with it. The pages of sign-in windows have their own navigation delegate (host: this
/// manager, `+TabHost`); never saved nor restored.
@MainActor
final class PopupWindowManager: PopupWindowHosting {
    let faviconService: FaviconService
    /// Window their downloads go back to: the session's.
    let downloadScope: DownloadScope
    /// Per-site page zoom of the session (task 5.4).
    let siteZooms: SiteZoomStore?
    /// Private window: dark sign-in windows, like it.
    let isPrivate: Bool
    /// Blocker of the session (task 6.2), given by the session; nil (tests): pages are not tracked.
    var contentBlocking: ContentBlockerScope?
    /// Navigation delegate of the sign-in windows' pages.
    let coordinator: NavigationCoordinator
    /// Open windows, from oldest to newest.
    private(set) var windows: [PopupWindowController] = []

    /// Shows the window above its originating window (replaced in tests: no window on screen).
    var present: @MainActor (PopupWindowController) -> Void = PopupWindowManager.presentOnScreen
    /// Usable area of the screen of the originating window, or of the pointer's screen without it (replaced in tests).
    var visibleScreenFrame: @MainActor (NSWindow?) -> CGRect? = PopupWindowManager.visibleFrame(around:)

    init(settings: PopupWindowSettings) {
        faviconService = settings.services.favicons
        downloadScope = settings.downloadScope
        siteZooms = settings.siteZooms
        isPrivate = settings.isPrivate
        coordinator = settings.services.makeCoordinator()
        coordinator.tabHost = self
    }

    func window(for webView: WKWebView) -> PopupWindowController? {
        windows.first { $0.tab.webView === webView }
    }

    func window(for page: BrowserTab) -> PopupWindowController? {
        windows.first { $0.tab === page }
    }

    /// True if a window opened by `page` is still open: `page` must not be suspended (task 5.6), otherwise
    /// `window.opener` would no longer find it.
    func hasOpenWindow(openedBy page: BrowserTab) -> Bool {
        windows.contains { $0.opener.page === page }
    }

    // MARK: Opening

    /// Opens a sign-in window and returns its web view, created with `configuration` as is (otherwise
    /// `window.opener` does not work); WebKit then loads the requested page in it.
    func open(configuration: WKWebViewConfiguration, features: PopupWindowFeatures, opener: PopupOpener) -> WKWebView {
        let tab = BrowserTab(configuration: configuration, openerID: opener.page?.id)
        return show(tab, features: features, opener: opener).tab.makeWebViewIfNeeded()
    }

    /// Creates the window of `tab`, at the requested size, centered on the originating window, and shows it.
    @discardableResult
    func show(_ tab: BrowserTab, features: PopupWindowFeatures, opener: PopupOpener) -> PopupWindowController {
        tab.delegate = coordinator
        // Web view created before the window, with its delegate: the container shows it from the opening.
        tab.makeWebViewIfNeeded()
        let controller = PopupWindowController(
            tab: tab,
            opener: opener,
            frame: frame(for: features, opener: opener.window),
            isPrivate: isPrivate,
            manager: self,
        )
        windows.append(controller)
        present(controller)
        return controller
    }

    // MARK: Closing

    func didClose(_ controller: PopupWindowController) {
        windows.removeAll { $0 === controller }
    }

    /// Private window closed: its sign-in windows too (its session is forgotten).
    func closeAll() {
        for controller in windows {
            controller.close()
        }
    }

    /// Profile deleted: the windows that use its data close before the data is erased.
    func closeWindows(using dataStore: WKWebsiteDataStore) {
        for controller in windows where controller.tab.configuration.websiteDataStore === dataStore {
            controller.close()
        }
    }

    // MARK: Screen

    /// Page at the requested size, plus the address bar and the title bar, within the usable area of the screen.
    private func frame(for features: PopupWindowFeatures, opener: NSWindow?) -> CGRect {
        let page = PopupWindowPlacement.pageSize(for: features)
        let content = CGRect(x: 0, y: 0, width: page.width, height: page.height + PopupAddressBar.height)
        let size = NSWindow.frameRect(forContentRect: content, styleMask: PopupWindow.style).size
        let visible = visibleScreenFrame(opener) ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return PopupWindowPlacement.frame(size: size, opener: opener?.frame, in: visible)
    }

    /// Above the originating window if it is on screen, in front; the page takes keyboard focus.
    static func presentOnScreen(_ controller: PopupWindowController) {
        if let parent = controller.opener.window, parent.isVisible, !parent.isMiniaturized {
            controller.attach(to: parent)
        }
        controller.window.makeKeyAndOrderFront(nil)
        TabActivation.focusPage(of: controller.tab)
    }

    static func visibleFrame(around window: NSWindow?) -> CGRect? {
        window?.screen?.visibleFrame ?? MiniWindowManager.screenUnderPointer()
    }
}
