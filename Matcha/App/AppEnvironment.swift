import Foundation

/// The app's composition root (audit C2): the shared services, made once in `MatchaApp.init` and handed to whoever
/// needs them (initializers, `.environment`), never reached through a `static let shared`.
@MainActor
final class AppEnvironment {
    /// Icons of the websites, cached on disk.
    let favicons = FaviconService(directory: FaviconService.defaultDirectory)
    let downloads = DownloadManager()
    /// The blocker, while it is available (task 6.2, set aside).
    let contentBlocker = ContentBlockerService.isAvailable ? ContentBlockerService(defaults: .standard) : nil
    let extensions: ExtensionManager
    /// Configuration of every page: source viewer and extensions.
    let pages: WebConfigurationFactory
    /// Dialogs and panels of the pages.
    let pageDialogs = SystemPageDialogs()

    init() {
        let extensions = ExtensionManager.shared
        self.extensions = extensions
        pages = WebConfigurationFactory { extensions.attach(to: $0) }
    }

    /// What each browser session gets: these services, the system's dialogs and its own sign-in windows.
    var sessionServices: SessionServices {
        SessionServices(
            pages: pages,
            favicons: favicons,
            downloads: downloads,
            contentBlocker: contentBlocker,
            dialogs: pageDialogs,
            makePopupWindows: { PopupWindowManager(settings: $0) },
        )
    }
}
