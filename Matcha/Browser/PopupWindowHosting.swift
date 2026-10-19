import WebKit

/// Sign-in windows of a session (task 5.8), as the pages and the session see them: windows are interface
/// (`PopupWindowManager`), made by the app for each session (`SessionServices.makePopupWindows`, audit C1).
@MainActor
protocol PopupWindowHosting: AnyObject {
    /// Blocker of the session (task 6.2), given by the session.
    var contentBlocking: ContentBlockerScope? { get set }
    /// Opens a sign-in window and returns its web view, created with `configuration` as is (otherwise `window.opener`
    /// does not work).
    func open(configuration: WKWebViewConfiguration, features: PopupWindowFeatures, opener: PopupOpener) -> WKWebView
    /// True if a window opened by `page` is still open: `page` must not be suspended (task 5.6).
    func hasOpenWindow(openedBy page: BrowserTab) -> Bool
    /// Closes the windows whose pages use `dataStore` (profile deleted).
    func closeWindows(using dataStore: WKWebsiteDataStore)
    /// Closes every window (private window closed).
    func closeAll()
}

/// What a session gives its sign-in windows.
@MainActor
struct PopupWindowSettings {
    let services: SessionServices
    /// Window their downloads go back to: the session's.
    let downloadScope: DownloadScope
    /// Per-site page zoom of the session (task 5.4).
    let siteZooms: SiteZoomStore?
    /// Private window: dark sign-in windows, like it.
    let isPrivate: Bool
}
