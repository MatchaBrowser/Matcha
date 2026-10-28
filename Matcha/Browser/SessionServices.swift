import WebKit

/// What the app gives each browser session (audits C1 and C2): the services made once at launch (`AppEnvironment`)
/// and the parts of the interface that pages call (dialogs, sign-in windows). Handed down to the Spaces, their tabs
/// and their navigation delegate; the tests make their own, with no extension, download or window.
@MainActor
struct SessionServices {
    /// Configuration of the pages (source viewer, extensions).
    var pages: WebConfigurationFactory
    /// Icons of the websites (a private session makes its own, in memory).
    var favicons: FaviconService
    /// The app's downloads; nil: pages can't download.
    var downloads: DownloadManager?
    /// The app's blocker, while it is available (`ContentBlockerService.isAvailable`).
    var contentBlocker: ContentBlockerService?
    /// JavaScript dialogs, files to send, logins, saving and printing of the pages.
    var dialogs: any PageDialogPresenting
    /// Notifications of the pages; nil: they read “denied”.
    var notifications: PageNotificationCenter?
    /// Today tabs of the account's other Macs, offered by the command bar; nil: none.
    var otherMacs: OtherMacsTabs?
    /// Languages of the pages' translation (task 9.3).
    var translationLanguages: TranslationLanguages
    /// Sign-in windows of a session; nil: a window opened with a size becomes a tab.
    var makePopupWindows: @MainActor (PopupWindowSettings) -> (any PopupWindowHosting)?
    /// A page closes its Peek (`window.close()`): the interface also gives keyboard focus back to the page under it
    /// (`PeekActions`, review CO1); without interface, the Peek just closes.
    var closePeek: @MainActor (TabManager) -> Void

    init(
        pages: WebConfigurationFactory = WebConfigurationFactory(),
        favicons: FaviconService = FaviconService(directory: nil),
        downloads: DownloadManager? = nil,
        contentBlocker: ContentBlockerService? = nil,
        dialogs: any PageDialogPresenting = UnavailablePageDialogs(),
        notifications: PageNotificationCenter? = nil,
        otherMacs: OtherMacsTabs? = nil,
        translationLanguages: TranslationLanguages = TranslationLanguages(),
        makePopupWindows: @escaping @MainActor (PopupWindowSettings) -> (any PopupWindowHosting)? = { _ in nil },
        closePeek: @escaping @MainActor (TabManager) -> Void = { $0.closePeek() },
    ) {
        self.pages = pages
        self.favicons = favicons
        self.downloads = downloads
        self.contentBlocker = contentBlocker
        self.dialogs = dialogs
        self.notifications = notifications
        self.otherMacs = otherMacs
        self.translationLanguages = translationLanguages
        self.makePopupWindows = makePopupWindows
        self.closePeek = closePeek
    }

    /// Navigation delegate of pages, with these services.
    func makeCoordinator() -> NavigationCoordinator {
        let coordinator = NavigationCoordinator()
        coordinator.dialogs = dialogs
        coordinator.downloadManager = downloads
        coordinator.notificationCenter = notifications
        return coordinator
    }
}
