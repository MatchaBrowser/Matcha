import AppKit
import KeyboardShortcuts
import Observation
import OSLog
import WebKit

/// The app's mini windows (equivalent of Little Arc): global shortcut, creation, active window, floating level, and
/// link with the main window for “Open in Space” (`+HandOff`). A single instance, created by `MatchaApp`; mini
/// windows are never private, saved or restored.
@MainActor
@Observable
final class MiniWindowManager {
    /// Where an opening comes from (log only).
    enum Source: String {
        case shortcut, menu, page, link
    }

    @ObservationIgnored let session: BrowserSession
    /// Where to remember the size chosen with the mouse; nil with a test database (nothing is remembered).
    @ObservationIgnored let defaults: UserDefaults?
    /// Navigation delegate of the mini windows' pages (host: this manager).
    @ObservationIgnored let coordinator = NavigationCoordinator()
    /// Open mini windows, from the oldest to the most recent.
    @ObservationIgnored private(set) var windows: [MiniWindowController] = []
    /// Active mini window, tracked so the menus update; the action reads `keyWindow` again.
    private(set) var keyWindowID: MiniWindowController.ID?
    /// Main browsing window (never a private window); the “Open in …” button follows it.
    private(set) var mainWindow: (any MainWindowLink)?
    /// Space displayed by the main window when it closed (at launch: the remembered one).
    @ObservationIgnored var lastMainSpaceID: UUID?
    /// Page to show as soon as the main window reopens.
    @ObservationIgnored var pendingReveal: (spaceID: UUID, tab: BrowserTab)?
    /// Reopens the closed main window; provided by it when it appears.
    @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?

    /// WebKit configuration of a new page, for its profile's store (replaced in tests).
    @ObservationIgnored var makeConfiguration: @MainActor (WKWebsiteDataStore) -> WKWebViewConfiguration =
        WebConfigurationFactory.makeConfiguration(websiteDataStore:)
    /// Shows a panel and activates the app (replaced in tests: no panel on screen).
    @ObservationIgnored var present: @MainActor (MiniWindowPanel) -> Void = MiniWindowManager.presentOnScreen
    /// Usable area of the screen where to open a mini window: that of the pointer.
    @ObservationIgnored var visibleScreenFrame: @MainActor () -> CGRect? = MiniWindowManager.screenUnderPointer
    /// Engine and suggestions, read each time the bar opens.
    @ObservationIgnored var commandBarSettings: @MainActor () -> CommandBarSettings = { MiniWindowSettings.current() }

    @ObservationIgnored private var shortcutTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    /// Free of side effects: `start()` hooks up the global shortcut and the app's activation.
    init(session: BrowserSession, defaults: UserDefaults?) {
        self.session = session
        self.defaults = defaults
        lastMainSpaceID = defaults?.string(forKey: WindowModel.currentSpaceKey).flatMap(UUID.init(uuidString:))
        coordinator.tabHost = self
    }

    /// Listens to the global shortcut (even when Matcha is not in the foreground) and to the app's activation.
    /// No effect on a second call; never called in the unit tests' host app.
    func start() {
        guard shortcutTask == nil else {
            return
        }
        MiniWindowShortcut.removeFormerDefault()
        MenuShortcutStore.shared.setGlobalMiniWindowKey(MiniWindowShortcut.menuKey(of: KeyboardShortcuts.getShortcut(for: .openMiniWindow)))
        shortcutTask = Task { [weak self] in
            for await _ in KeyboardShortcuts.events(.keyDown, for: .openMiniWindow) {
                guard let self else {
                    return
                }
                // During a modal alert (“Quit Matcha?”), no window would take the keyboard.
                guard NSApp.modalWindow == nil else {
                    Logger.miniWindow.notice("Raccourci de la mini-fenêtre ignoré pendant une alerte")
                    continue
                }
                openNew(source: .shortcut)
            }
        }
        observe(NSApplication.didResignActiveNotification) { MiniWindowLevels.lower($0.windows.map(\.panel)) }
        observe(NSApplication.didBecomeActiveNotification) { MiniWindowLevels.raise($0.windows.map(\.panel)) }
    }

    // MARK: Windows

    /// Active mini window, read at the time of the action.
    var keyWindow: MiniWindowController? {
        windows.first { $0.panel.isKeyWindow }
    }

    func window(for tab: BrowserTab) -> MiniWindowController? {
        windows.first { $0.tab === tab }
    }

    func window(for webView: WKWebView) -> MiniWindowController? {
        windows.first { $0.tab.webView === webView }
    }

    // MARK: Opening

    /// ⌥⌘N, File menu: an empty mini window, bar open, in the profile of the displayed Space (never private).
    /// `url` (task 8.2: links coming from other apps): the page loads, the bar stays closed.
    @discardableResult
    func openNew(loading url: URL? = nil, source: Source) -> MiniWindowController {
        let profile = displayedSpace.record.profile
        let tab = BrowserTab(configuration: makeConfiguration(session.dataStore(for: profile)))
        let controller = show(tab, profileID: profile?.id)
        if let url {
            tab.load(url)
            controller.showWebView()
        } else {
            controller.showCommandBar(.newSearch)
        }
        Logger.miniWindow.info("Mini-fenêtre ouverte (\(source.rawValue, privacy: .public))")
        return controller
    }

    /// Creates the panel of `tab`, offset from the last opened mini window, and shows it in the foreground.
    @discardableResult
    func show(_ tab: BrowserTab, profileID: UUID?) -> MiniWindowController {
        tab.delegate = coordinator
        let size = MiniWindowPlacement.storedSize(defaults?.string(forKey: MiniWindowPlacement.sizeKey)) ?? MiniWindowPlacement.defaultSize
        let visible = visibleScreenFrame() ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = MiniWindowPlacement.frame(size: size, in: visible, after: windows.last?.panel.frame)
        let controller = MiniWindowController(tab: tab, profileID: profileID, frame: frame, manager: self)
        windows.append(controller)
        present(controller.panel)
        return controller
    }

    // MARK: Tracking

    func keyChanged(_ controller: MiniWindowController, isKey: Bool) {
        if isKey {
            keyWindowID = controller.id
        } else if keyWindowID == controller.id {
            keyWindowID = nil
        }
    }

    func didClose(_ controller: MiniWindowController) {
        windows.removeAll { $0 === controller }
        if keyWindowID == controller.id {
            keyWindowID = nil
        }
    }

    /// Size chosen with the mouse: the next mini window reuses it (never with a test database).
    func rememberSize(_ size: CGSize) {
        defaults?.set(NSStringFromSize(size), forKey: MiniWindowPlacement.sizeKey)
    }

    /// Primitive for `+HandOff`: main window reported or gone.
    func setMainWindow(_ link: (any MainWindowLink)?) {
        mainWindow = link
    }

    /// Deleted profile: its mini windows close before its data is deleted.
    func closeWindows(ofProfile profileID: UUID) {
        for controller in windows where controller.profileID == profileID {
            controller.close()
        }
    }

    // MARK: Screen

    static func presentOnScreen(_ panel: MiniWindowPanel) {
        panel.makeKeyAndOrderFront(nil)
        // Shortcut pressed in another app: cooperative activation (`NSApp.activate()`) is refused there and the
        // mini window would not get the keyboard. `activate(ignoringOtherApps:)` is marked
        // `API_TO_BE_DEPRECATED` in the SDK, with no warning at compile time.
        NSApp.activate(ignoringOtherApps: true)
    }

    static func screenUnderPointer() -> CGRect? {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame
    }

    private func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (MiniWindowManager) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self {
                    handle(self)
                }
            }
        })
    }
}
