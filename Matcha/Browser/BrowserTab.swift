import AppKit
import Observation
import OSLog
import WebKit

/// A running tab: it owns its web view and exposes its state to the interface.
/// The state is copied from the web view through KVO observation. The web view can be released
/// (`unload`, or `suspend` for memory) and then recreated on demand (`makeWebViewIfNeeded`).
@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id: UUID
    /// Tab this one was opened from (link, `window.open`), if any.
    let openerID: BrowserTab.ID?

    /// The tab's web view; nil when it is unloaded.
    private(set) var webView: WKWebView?
    private(set) var title: String?
    private(set) var url: URL?
    /// `url != nil`, tracked separately: a view that only needs to know whether the tab has an address
    /// (“Copy URL” menu) is not recomputed on every address change.
    private(set) var hasURL = false
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// The site's icon, provided by `FaviconService`; nil as long as it is not known.
    var favicon: Favicon?
    /// Original address and title of a pinned or favorite tab: it goes back to them when closed.
    var pinnedURL: URL?
    var pinnedTitle: String?
    /// Last time the tab was selected (restoring the selection, command bar ranking).
    var lastActivity = Date.now
    /// Navigation state kept for restoration (back/forward history, scrolling).
    var savedInteractionState: Data?
    /// The page's permission requests awaiting an answer (banner, task 5.2).
    let permissionPrompts = PermissionPromptQueue()
    /// Find in page (bar, text, result; task 5.3).
    let find = FindSession()
    /// Visits of the page recorded in the history (task 5.5).
    let history = PageHistory()
    /// Putting to sleep to save memory (task 5.6).
    let suspension = TabSuspension()
    /// Recovery after the page's process terminated (task 5.7).
    let crash = PageCrashRecovery()
    /// Sound played by the page: speaker icon in the sidebar (task 5.10).
    let audio = PageAudio()
    /// The page's zoom (`WKWebView.pageZoom`, task 5.4), copied here for the menus: it only changes through
    /// `setPageZoom`. Pinch zoom (`magnification`) is separate.
    private(set) var pageZoom = ZoomLevels.actualSize

    /// Navigation and UI delegate, attached to each web view created (and to the current view).
    @ObservationIgnored weak var delegate: (any WKNavigationDelegate & WKUIDelegate)? {
        didSet {
            webView?.navigationDelegate = delegate
            webView?.uiDelegate = delegate
        }
    }

    /// Configuration of the tab's web views (same profile, same settings on each recreation).
    @ObservationIgnored private(set) var configuration: WKWebViewConfiguration
    /// Address to load the next time the web view is created.
    @ObservationIgnored private var pendingURL: URL?
    /// State to restore the next time the web view is created, instead of reloading the address.
    @ObservationIgnored private var pendingInteractionState: Data?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// The first web view is created with exactly this configuration (required for `window.open`), unless its content
    /// controller is already used by another page: copy with a new controller (blocker, task 6.2).
    init(id: UUID = UUID(), configuration: WKWebViewConfiguration, openerID: BrowserTab.ID? = nil) {
        self.id = id
        self.configuration = WebConfigurationFactory.pageConfiguration(from: configuration)
        self.openerID = openerID
        find.performer = self
        history.page = self
        suspension.page = self
        crash.page = self
    }

    /// Tab restored from the saved data: it displays `url` and `title`, and only creates its web view
    /// (which will load `url`) the first time it is shown.
    convenience init(restoring stored: StoredTab, configuration: WKWebViewConfiguration) {
        self.init(id: stored.id, configuration: configuration)
        setURL(stored.url)
        title = stored.title
        pendingURL = stored.url
        pinnedURL = stored.pinnedURL
        pinnedTitle = stored.pinnedTitle
        lastActivity = stored.lastActivity
        savedInteractionState = stored.interactionState
        pendingInteractionState = stored.interactionState
    }

    var isLoaded: Bool {
        webView != nil
    }

    /// Displayed as loaded in the sidebar (full title, close button): web view present, or put to sleep to save
    /// memory, which must not change anything in the display (task 5.6).
    var appearsLoaded: Bool {
        webView != nil || suspension.isSuspended
    }

    /// The tab's web view, created if needed; an unloaded tab then reloads its address, a sleeping tab its page and
    /// its history, without counting a new visit.
    @discardableResult
    func makeWebViewIfNeeded() -> WKWebView {
        if let webView {
            return webView
        }
        let webView = BrowserWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.pageZoom = pageZoom
        webView.audio = audio
        // Reusable copy for the next views (reload, duplication).
        configuration = webView.configuration
        self.webView = webView
        if suspension.isSuspended {
            // Before observing: the empty title and missing address of the new view do not replace the tab's.
            suspension.didResume(url: url)
            history.pageWillResume(url: url)
        }
        observe(webView)
        if let state = pendingInteractionState {
            // Restoration: page, history and scrolling, without reloading from the address.
            pendingInteractionState = nil
            pendingURL = nil
            webView.interactionState = state
        } else if let pendingURL {
            self.pendingURL = nil
            load(pendingURL, in: webView)
        }
        return webView
    }

    /// Keeps the web view's navigation state, to restore it later; false if it could not be read.
    @discardableResult
    func captureInteractionState() -> Bool {
        guard let webView else {
            return false
        }
        guard let state = webView.interactionState as? Data else {
            Logger.browser.notice("État de navigation illisible : l'onglet sera restauré depuis son adresse")
            return false
        }
        savedInteractionState = state
        return true
    }

    /// Releases the web view (memory, sound, process), denies pending permission requests, forgets find in page and
    /// goes back to 100% (the site's zoom will come back with the page). The tab now displays `url` and `title`, and
    /// will load `url` when it is reopened.
    func unload(resettingTo url: URL?, title: String?) {
        releaseWebView()
        history.reset()
        suspension.reset()
        pendingURL = url
        // Back to the original address: the history is forgotten.
        pendingInteractionState = nil
        savedInteractionState = nil
        setURL(url)
        self.title = title
        canGoBack = false
        canGoForward = false
        pageZoom = ZoomLevels.actualSize
    }

    /// Puts the tab to sleep to save memory (task 5.6): its navigation state is kept and its web view released, like
    /// `unload`, but it keeps its address, title, icon, zoom and back/forward history.
    /// Once recreated, it reopens the same page (from its address if the state could not be read). `snapshot`: its
    /// snapshot.
    func suspend(snapshot: TabSnapshot?, at date: Date = .now) {
        guard webView != nil else {
            return
        }
        if !captureInteractionState() {
            // A state older than the displayed page (kept at the last load) must not replace it.
            savedInteractionState = nil
        }
        releaseWebView()
        history.reset()
        pendingURL = url
        pendingInteractionState = savedInteractionState
        suspension.didSuspend(snapshot: snapshot, at: date)
    }

    /// Reads the web view's title and address again (end of the reload of a tab woken from sleep). A view without an
    /// address (failed reload) does not empty the tab.
    func syncWithWebView() {
        guard let webView, webView.url != nil else {
            return
        }
        title = webView.title
        setURL(webView.url)
    }

    func load(_ url: URL) {
        let webView = makeWebViewIfNeeded()
        // A page other than the one put to sleep: no more snapshot on top; a crashed page leaves its message.
        suspension.endRestoring()
        crash.pageWillNavigate()
        load(url, in: webView)
    }

    /// The page's zoom (100% = 1); kept for the web view recreated after an unload.
    func setPageZoom(_ zoom: Double) {
        if pageZoom != zoom {
            pageZoom = zoom
        }
        webView?.pageZoom = zoom
    }

    /// Releases the web view: observation, sound (icon included), loading, delegates; denies pending permission
    /// requests, forgets find in page and the recovery from a process termination (message included).
    private func releaseWebView() {
        observations = []
        permissionPrompts.denyAll()
        find.reset()
        audio.reset()
        if let webView {
            (webView as? BrowserWebView)?.audio = nil
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        webView = nil
        isLoading = false
        progress = 0
        crash.end()
    }

    private func load(_ url: URL, in webView: WKWebView) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// `hasURL` is only modified (and only notifies its observers) if the tab gains or loses its address. Another
    /// address makes the last find-in-page result obsolete.
    private func setURL(_ newURL: URL?) {
        if newURL != url {
            find.pageDidChange()
        }
        url = newURL
        let hasNewURL = newURL != nil
        if hasURL != hasNewURL {
            hasURL = hasNewURL
        }
    }

    private func observe(_ webView: WKWebView) {
        observations = [
            webView.observe(\.title, options: .initial, changeHandler: sync { tab, webView in
                // Waking from sleep, process termination: the tab keeps its title until the reloaded page has one.
                if tab.keepsTitleAndAddress, webView.title?.isEmpty != false {
                    return
                }
                tab.title = webView.title
                tab.history.titleDidChange(to: webView.title, pageURL: webView.url)
            }),
            webView.observe(\.url, options: .initial, changeHandler: sync { tab, webView in
                if tab.keepsTitleAndAddress, webView.url == nil {
                    return
                }
                tab.suspension.pageURLDidChange(to: webView.url)
                tab.setURL(webView.url)
                // Loading read from the web view: WebKit changes the address and the loading state together, before
                // the tab has copied the latter.
                tab.history.urlDidChange(to: webView.url, isLoading: webView.isLoading)
            }),
            webView.observe(\.isLoading, options: .initial, changeHandler: sync { $0.isLoading = $1.isLoading }),
            webView.observe(\.estimatedProgress, options: .initial, changeHandler: sync { $0.progress = $1.estimatedProgress }),
            webView.observe(\.canGoBack, options: .initial, changeHandler: sync { $0.canGoBack = $1.canGoBack }),
            webView.observe(\.canGoForward, options: .initial, changeHandler: sync { $0.canGoForward = $1.canGoForward }),
        ]
    }

    /// Makes a KVO handler that copies the web view's state into the tab.
    /// WebKit sends its KVO notifications on the main thread. A view already replaced is ignored.
    private func sync<Value>(
        _ apply: @escaping @MainActor @Sendable (BrowserTab, WKWebView) -> Void,
    ) -> @Sendable (WKWebView, NSKeyValueObservedChange<Value>) -> Void {
        { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self, self.webView === webView else {
                    return
                }
                apply(self, webView)
            }
        }
    }
}
