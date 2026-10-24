import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct MatchaApp: App {
    static let browserWindowID = "browser"
    static let privateWindowID = "private"
    static let historyWindowID = "history"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(BrowserSettings.Key.appearance) private var appearance = BrowserSettings.appearance
    /// Shared services, made once (audit C2).
    @State private var environment: AppEnvironment
    @State private var session: BrowserSession
    /// Mini windows of the whole app (task 4.5).
    @State private var miniWindows: MiniWindowManager

    init() {
        // The tabs are ours: no macOS window tabs (“Show Tab Bar”).
        NSWindow.allowsAutomaticWindowTabbing = false
        // UI tests: their downloads folder starts out empty again (no effect otherwise).
        DownloadLocation.resetTestSubfolderIfRequested()
        let environment = AppEnvironment()
        // Store unreadable and the user chose to quit (audit R2): nothing was opened, nothing to save.
        guard let session = BrowserSession.launch(onFailure: StoreFailureAlert.ask, services: environment.sessionServices) else {
            exit(EXIT_SUCCESS)
        }
        // History read at launch, off the main thread, after deleting visits older than a year: the command bar
        // finds it ready.
        if let history = session.history {
            Task { await history.load() }
        }
        // Nothing is remembered (size, displayed Space) with a test store.
        let miniWindows = MiniWindowManager(session: session, defaults: session.isInMemory ? nil : .standard)
        // Downloads list kept from one launch to the next, except there too.
        if !session.isInMemory {
            environment.downloads.restoreList(from: .standard)
        }
        // Global mini window shortcut, except in the unit tests' host app: it would be taken from the user, and its
        // first access would write ⌥⌘N into their settings (same app identifier). Blocker (task 6.2, set aside):
        // lists read again or compiled in the background, except there too (the tests have their own store).
        if !TestEnvironment.isUnitTestHost() {
            miniWindows.start()
            let global = KeyboardShortcuts.getShortcut(for: .openMiniWindow)
            environment.menuShortcuts.setGlobalMiniWindowKey(MiniWindowShortcut.menuKey(of: global))
            environment.contentBlocker?.start()
        }
        // Extensions (task 6.3): mini windows are windows to them; installed extensions load in the background,
        // except with a test store (UI tests): never the user's.
        environment.extensionWindows.miniWindows = miniWindows
        if !session.isInMemory {
            environment.extensions.start()
            // Sync (tasks 7.7 and 7.9): never with a test store.
            environment.sync.start(session: session)
        }
        // Edit > Find: the active mini window's page first.
        environment.pageFind.miniWindows = miniWindows
        _environment = State(initialValue: environment)
        _session = State(initialValue: session)
        _miniWindows = State(initialValue: miniWindows)
        appDelegate.pageFind = environment.pageFind
        // Links from other apps (task 8.2), including the one that launched the app.
        appDelegate.incomingLinks.handler = { [miniWindows] urls in
            miniWindows.openFromOtherApp(urls, destination: ExternalLinkDestination.current())
        }
    }

    var body: some Scene {
        // A single main window until sharing Spaces between windows is defined.
        Window(Text(verbatim: "Matcha"), id: Self.browserWindowID) {
            BrowserWindowView(session: session)
                .environment(miniWindows)
                .appServices(environment)
        }
        .windowStyle(.hiddenTitleBar)
        // First opening: most of the screen, up to a comfortable size (audit H5); then the size the user chose.
        .defaultWindowPlacement { _, context in
            WindowPlacement(size: BrowserWindowSize.defaultSize(visible: context.defaultDisplay.visibleRect.size))
        }
        // Links from other apps go through the delegate (`IncomingLinks`): no window is created for them.
        .handlesExternalEvents(matching: [])
        .commands {
            BrowserCommands(
                miniWindows: miniWindows,
                shortcuts: environment.menuShortcuts,
                settingsSelection: environment.settingsSelection,
            )
        }
        .onChange(of: appearance, initial: true) { appearance.apply() }

        // Private windows: each one has its own in-memory session, nothing is saved; never reopened at launch, like
        // in Safari.
        WindowGroup("Private Browsing", id: Self.privateWindowID) {
            PrivateWindowView(services: environment.sessionServices)
                .appServices(environment)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultWindowPlacement { _, context in
            WindowPlacement(size: BrowserWindowSize.defaultSize(visible: context.defaultDisplay.visibleRect.size))
        }
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
        // Without its default commands (“Close”, “Close All”), which would override ⌘W and ⇧⌘W.
        .commandsRemoved()

        // History (⌘Y, task 5.5): a single window, opened only by the user, never at launch nor restored; without
        // commands of its own (no extra item in the Window menu).
        Window(Text("History"), id: Self.historyWindowID) {
            HistoryWindow(session: session)
                .environment(miniWindows)
        }
        .defaultSize(width: 760, height: 560)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
        .commandsRemoved()

        Settings {
            SettingsView(
                selection: environment.settingsSelection,
                extensions: environment.extensions,
                extensionSync: environment.extensionSync,
                menuShortcuts: environment.menuShortcuts,
                shortcutRecorder: environment.shortcutRecorder,
            )
            .environment(session)
            .environment(miniWindows)
            .environment(environment.sync)
        }
    }
}
