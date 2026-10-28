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
    /// The web view's address: that of a load as soon as it starts. For saving, history and sync only: what is shown or
    /// copied reads `displayedURL`, what acts on the displayed page reads `documentURL` (audit W4, review TR1).
    private(set) var url: URL?
    /// Address to show (address pill, Peek, sign-in windows, security): the displayed document's (audit W4).
    private(set) var displayedAddress = DisplayedAddress()
    /// True if everything the displayed page loaded came encrypted (`+Address`, audit W5).
    private(set) var hasOnlySecureContent = false
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
    /// Downloads started by the page's document, and those waiting for the user (audit W7).
    let pageDownloads = PageDownloads()
    /// Load that failed, shown in place of the page (`+LoadFailure`, audit K5).
    let loadFailure = PageLoadFailure()
    /// JavaScript dialogs of the page's document (audit K1).
    let pageDialogs = PageDialogState()
    /// A local page that refers to files it can't read (banner, review WB11).
    let localFiles = PageLocalFiles()
    /// Translation of the page (task 9.2).
    let translation = PageTranslation()
    /// The displayed document came over a certificate the user accepted for its website (“Not Secure”, audit K5); read
    /// from the document's own connection, whichever tab accepted it (`NavigationCoordinator+Authentication`, WB5).
    var usesAcceptedCertificate = false
    /// A new web view of a tab that already has a title or an address (restored, unloaded) hasn't shown a document
    /// yet: its empty title and missing address don't replace the tab's (review WB19).
    @ObservationIgnored private(set) var awaitsFirstDocument = false
    /// What the tab's local file may read, granted at its first load (`FileReadAccess`); nil for a website.
    private(set) var fileReadAccess: URL?
    /// The displayed website may send notifications (`NavigationCoordinator+Notifications`): never put to sleep.
    var canSendNotifications = false
    /// The page's zoom (`WKWebView.pageZoom`, task 5.4), copied here for the menus: it only changes through
    /// `setPageZoom`. Pinch zoom (`magnification`) is separate.
    private(set) var pageZoom = ZoomLevels.actualSize

    /// Navigation and UI delegate, attached to each web view created (and to the current view).
    @ObservationIgnored weak var delegate: (any WKNavigationDelegate & WKUIDelegate & PageNotificationReceiving)? {
        didSet {
            webView?.navigationDelegate = delegate
            webView?.uiDelegate = delegate
            (webView as? BrowserWebView)?.notifications = delegate
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
    /// (which will load `url`) the first time it is shown. From saved data (`isSaved`: launch, sync), an address of
    /// another kind (`StoredTab.restorable`, review WB12) comes back as an empty tab, without its history; a tab closed
    /// in this session (kept in memory) comes back as it was.
    convenience init(restoring stored: StoredTab, configuration: WKWebViewConfiguration, isSaved: Bool = true) {
        self.init(id: stored.id, configuration: configuration)
        let served = Self.servedSchemes(of: configuration, among: [stored.url, stored.pinnedURL])
        let restorable = { (url: URL?) in isSaved ? StoredTab.restorable(url, servedSchemes: served) : url }
        let url = restorable(stored.url)
        setURL(url)
        displayedAddress.reset(to: url)
        title = stored.title
        pendingURL = url
        pinnedURL = restorable(stored.pinnedURL)
        pinnedTitle = stored.pinnedTitle
        lastActivity = stored.lastActivity
        let state = url == nil ? nil : stored.interactionState
        savedInteractionState = state
        pendingInteractionState = state
        fileReadAccess = stored.fileReadAccess
        // A source viewer the user had opened stays readable after a relaunch: only the app saves such an address, a
        // page can't navigate to one (review WB3).
        if let url {
            PageSourceSchemeHandler.of(configuration)?.authorize(url, in: configuration.websiteDataStore)
        }
    }

    /// The tab's web view, created if needed: an unloaded tab then loads its address again (a new visit); a sleeping
    /// tab gets its page and its history back, without counting a new visit.
    @discardableResult
    func makeWebViewIfNeeded() -> WKWebView {
        if let webView {
            return webView
        }
        // A failure shown belongs to the previous view (review WB20).
        loadFailure.clear()
        let webView = BrowserWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.notifications = delegate
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
        // Before the observation, whose first notification gives the new view's empty address.
        let shownURL = displayedURL
        awaitsFirstDocument = title != nil || url != nil
        observe(webView)
        if let state = pendingInteractionState {
            // Restoration: page, history and scrolling, without reloading from the address. The tab's own page, shown
            // while it comes back.
            let savedURL = pendingURL ?? url
            pendingInteractionState = nil
            pendingURL = nil
            webView.interactionState = state
            if let shownURL {
                displayedAddress.userDidRequest(shownURL)
            }
            // A state WebKit can't read restores no history (the list is restored at once, the page loads later): the
            // saved address loads instead (review WB19).
            if webView.backForwardList.currentItem == nil, let savedURL {
                Logger.browser.notice("Unreadable navigation state: the tab loads its address")
                load(savedURL, in: webView)
            }
        } else if let pendingURL {
            self.pendingURL = nil
            displayedAddress.userDidRequest(pendingURL)
            load(pendingURL, in: webView)
        }
        return webView
    }

    /// Releases the web view (memory, sound, process), denies pending permission requests, forgets find in page and
    /// goes back to 100% (the site's zoom will come back with the page). The tab now displays `url` and `title`, and
    /// will load `url` when it is reopened.
    func unload(resettingTo url: URL?, title: String?) {
        releaseWebView()
        // The failure was the released view's: ⌘R loads `url` again, not the address that failed (review WB20).
        loadFailure.clear()
        history.reset()
        suspension.reset()
        pendingURL = url
        // Back to the original address: the history is forgotten.
        pendingInteractionState = nil
        savedInteractionState = nil
        setURL(url)
        displayedAddress.reset(to: url)
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

    /// The tab goes away for good (closed, deleted, removed by sync): its web view is released right away, as in
    /// `unload`, without waiting for the tab to be freed. A view still held elsewhere (window, SwiftUI, WebKit) would
    /// otherwise keep its page running, sound included.
    func discard() {
        releaseWebView()
    }

    /// Reads the web view's title and address again (end of the reload of a tab woken from sleep). A view without an
    /// address (failed reload) does not empty the tab.
    func syncWithWebView() {
        guard let webView, webView.url != nil else {
            return
        }
        title = webView.title
        setURL(webView.url)
        displayedAddress.reset(to: webView.url)
    }

    /// A new document is displayed, or the load ended: the address shown is the web view's again (audit W4).
    func documentDidChange() {
        awaitsFirstDocument = false
        displayedAddress.documentDidChange(to: webView?.url)
        loadFailure.clear()
        updateCanGoBack()
    }

    /// A first load that failed leaves the web view without an address: the tab keeps the one it couldn't open, to show
    /// it, save it and try again (audit K5).
    func keepFailedAddress(_ url: URL) {
        if webView?.url == nil {
            setURL(url)
        }
    }

    /// “Back” also leaves a failed load shown over the page it was leaving (audit K5).
    func updateCanGoBack() {
        canGoBack = webView?.canGoBack == true || (loadFailure.error != nil && webView?.url != nil)
    }

    /// Loads `url`; `source`: the page whose link it is, if any; `isFromAnotherApp`: received from another app. A local
    /// file then reads less (`FileReadAccess`).
    func load(_ url: URL, from source: URL? = nil, isFromAnotherApp: Bool = false) {
        let webView = makeWebViewIfNeeded()
        // A page other than the one put to sleep: no more snapshot on top; a crashed page leaves its message.
        suspension.endRestoring()
        crash.pageWillNavigate()
        displayedAddress.userDidRequest(url)
        loadFailure.clear()
        load(url, in: webView, from: source, isFromAnotherApp: isFromAnotherApp)
    }

    /// A local file the user chose again (banner of `localFiles`, “Choose File…” of an unreadable file): it reads its
    /// folder, as with ⌘O, whatever the tab was granted before.
    func openChosenFile(_ url: URL) {
        fileReadAccess = nil
        load(url)
    }

    /// The page's zoom (100% = 1); kept for the web view recreated after an unload.
    func setPageZoom(_ zoom: Double) {
        pageZoom = zoom
        webView?.pageZoom = zoom
    }

    /// Releases the web view: observation, sound (icon included), translation, loading, delegates; denies pending
    /// permission requests, ends the page's sheets, forgets find in page and the recovery from a process termination
    /// (message included).
    private func releaseWebView() {
        observations = []
        endPageRequests()
        find.reset()
        endPageActivity()
        if let webView {
            (webView as? BrowserWebView)?.audio = nil
            // Suspended rather than paused: if the view outlives the tab, its page cannot play again either.
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        webView = nil
        isLoading = false
        progress = 0
        crash.end()
    }

    private func load(_ url: URL, in webView: WKWebView, from source: URL? = nil, isFromAnotherApp: Bool = false) {
        if url.isFileURL {
            // Moved, or chosen before a relaunch outside the Downloads folder: WebKit would show nothing (review ON14).
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                loadFailure.show(PageLoadError(unreadableFile: url), serverTrust: nil, certificateExceptions: nil)
                keepFailedAddress(url)
                return
            }
            // The access granted the first time, for “Try Again”, a reload after a crash or an unload, a relaunch.
            let access = fileReadAccess.flatMap { FileReadAccess.covers($0, url) ? $0 : nil }
                ?? FileReadAccess.readableURL(for: url, openedFrom: source, isFromAnotherApp: isFromAnotherApp)
            fileReadAccess = access
            webView.loadFileURL(url, allowingReadAccessTo: access)
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
        hasURL = newURL != nil
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
                tab.displayedAddress.webViewURLDidChange(to: webView.url, isLoading: webView.isLoading)
                // Loading read from the web view: WebKit changes the address and the loading state together, before
                // the tab has copied the latter.
                tab.history.urlDidChange(to: webView.url, isLoading: webView.isLoading)
            }),
            webView.observe(\.isLoading, options: .initial, changeHandler: sync { $0.isLoading = $1.isLoading }),
            webView.observe(\.estimatedProgress, options: .initial, changeHandler: sync { $0.progress = $1.estimatedProgress }),
            webView.observe(\.canGoBack, options: .initial, changeHandler: sync { tab, _ in tab.updateCanGoBack() }),
            webView.observe(\.canGoForward, options: .initial, changeHandler: sync { $0.canGoForward = $1.canGoForward }),
            webView.observe(\.hasOnlySecureContent, options: .initial, changeHandler: sync { tab, webView in
                tab.hasOnlySecureContent = webView.hasOnlySecureContent
            }),
        ]
    }
}
