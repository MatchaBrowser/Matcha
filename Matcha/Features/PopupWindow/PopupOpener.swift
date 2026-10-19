import AppKit
import WebKit

/// Page that opened a sign-in window (task 5.8), recorded at opening: its host and its web view (where the sign-in
/// window's ⌘-click links and size-less windows go), its page (never suspended while the window is open, otherwise
/// `window.opener` would lose it: task 5.6), its window (above which the sign-in window stays), and what follows
/// its profile: permission decisions and history. The references are weak: the originating page can close before
/// the sign-in window, which then stays open.
@MainActor
struct PopupOpener {
    private(set) weak var host: (any TabHost)?
    private(set) weak var webView: WKWebView?
    private(set) weak var page: BrowserTab?
    private(set) weak var window: NSWindow?
    let sitePermissions: SitePermissionScope?
    let history: HistoryScope?

    init(host: any TabHost, webView: WKWebView) {
        self.host = host
        self.webView = webView
        page = host.page(for: webView)
        window = webView.window
        sitePermissions = host.sitePermissions(for: webView)
        history = host.historyScope(for: webView)
    }

    /// Host and web view of the originating page, if it still shows it (tab open, peek or mini window not closed).
    var liveSource: (host: any TabHost, webView: WKWebView)? {
        guard let host, let webView, host.page(for: webView) != nil else {
            return nil
        }
        return (host, webView)
    }
}
