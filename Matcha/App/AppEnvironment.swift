import Foundation
import WebKit

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

    /// The windows as extensions see them, and the pages opened for them.
    let extensionWindows: ExtensionWindows
    /// Sync of the extensions installed from a file.
    let extensionSync: ExtensionSyncAdapter
    /// Sync through a private server (tasks 7.7 and 7.9).
    let sync: SyncService
    /// Today tabs of the account's other Macs, filled by sync (`SYNC.md` § 2.4).
    let otherMacs = OtherMacsTabs()
    /// Tab shown by the Settings window.
    let settingsSelection = SettingsSelection()
    /// Shortcuts of the menu commands, and their recording (Settings > Shortcuts).
    let menuShortcuts = MenuShortcutStore(defaults: .standard)
    let shortcutRecorder = ShortcutRecorder()
    /// Edit > Find on the pages of the active window.
    let pageFind = PageFindResponder()
    /// Notifications of the websites, shown by macOS.
    let pageNotifications = PageNotificationCenter(system: UserNotificationsBridge())

    init() {
        let extensions = Self.makeExtensionManager()
        self.extensions = extensions
        extensionWindows = ExtensionWindows(sink: extensions.controller)
        extensionWindows.manager = extensions
        extensions.host = extensionWindows
        extensions.permissionPrompter = ExtensionPermissionAlert()
        extensionSync = Self.makeExtensionSync(manager: extensions)
        sync = SyncService(defaults: .standard, extensions: extensionSync, otherMacs: otherMacs, directory: Self.syncDirectory)
        pages = WebConfigurationFactory { extensions.attach(to: $0) }
    }

    /// `Application Support` of the app; nil during tests (unit tests and test store): nothing is written there.
    private static var applicationSupport: URL? {
        guard !TestEnvironment.usesInMemoryStore() else {
            return nil
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// `Application Support/Sync`.
    private static var syncDirectory: URL? {
        applicationSupport?.appendingPathComponent("Sync")
    }

    /// Settings of the signed-in account, in `Application Support/Sync` (`SyncService` picks the file when its sync
    /// starts, review SY11); during tests (unit tests and test store), in memory.
    private static func makeExtensionSync(manager: ExtensionManager) -> ExtensionSyncAdapter {
        ExtensionSyncAdapter(manager: manager, synced: SyncedExtensions(url: nil))
    }

    /// In the unit tests' host app and with a test store (UI tests), a non-persistent controller, with nothing saved or
    /// loaded (same settings and same container as the app).
    private static func makeExtensionManager() -> ExtensionManager {
        guard let applicationSupport else {
            return ExtensionManager(configuration: .nonPersistent(), store: ExtensionStateStore(defaults: nil), directory: nil)
        }
        return ExtensionManager(
            configuration: .default(),
            store: ExtensionStateStore(defaults: .standard),
            directory: ExtensionInstallDirectory.directory(in: applicationSupport),
        )
    }

    /// What each browser session gets: these services, the system's dialogs and its own sign-in windows.
    var sessionServices: SessionServices {
        SessionServices(
            pages: pages,
            favicons: favicons,
            downloads: downloads,
            contentBlocker: contentBlocker,
            dialogs: pageDialogs,
            notifications: pageNotifications,
            otherMacs: otherMacs,
            makePopupWindows: { PopupWindowManager(settings: $0) },
            closePeek: { PeekActions.close(in: $0) },
        )
    }
}
