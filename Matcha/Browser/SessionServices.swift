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
    /// Sign-in windows of a session; nil: a window opened with a size becomes a tab.
    var makePopupWindows: @MainActor (PopupWindowSettings) -> (any PopupWindowHosting)?

    init(
        pages: WebConfigurationFactory = WebConfigurationFactory(),
        favicons: FaviconService = FaviconService(directory: nil),
        downloads: DownloadManager? = nil,
        contentBlocker: ContentBlockerService? = nil,
        dialogs: any PageDialogPresenting = UnavailablePageDialogs(),
        notifications: PageNotificationCenter? = nil,
        otherMacs: OtherMacsTabs? = nil,
        makePopupWindows: @escaping @MainActor (PopupWindowSettings) -> (any PopupWindowHosting)? = { _ in nil },
    ) {
        self.pages = pages
        self.favicons = favicons
        self.downloads = downloads
        self.contentBlocker = contentBlocker
        self.dialogs = dialogs
        self.notifications = notifications
        self.otherMacs = otherMacs
        self.makePopupWindows = makePopupWindows
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
