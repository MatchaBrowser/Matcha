import AppKit
import SwiftUI

@main
struct MatchaApp: App {
    static let browserWindowID = "browser"
    static let privateWindowID = "private"
    static let historyWindowID = "history"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(BrowserSettings.Key.appearance) private var appearance = BrowserSettings.appearance
    @State private var session: BrowserSession
    /// Mini windows of the whole app (task 4.5).
    @State private var miniWindows: MiniWindowManager

    init() {
        // The tabs are ours: no macOS window tabs (“Show Tab Bar”).
        NSWindow.allowsAutomaticWindowTabbing = false
        // UI tests: their downloads folder starts out empty again (no effect otherwise).
        DownloadLocation.resetTestSubfolderIfRequested()
        // Store unreadable and the user chose to quit (audit R2): nothing was opened, nothing to save.
        guard let session = BrowserSession.launch() else {
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
            DownloadManager.shared.restoreList(from: .standard)
        }
        // Global mini window shortcut, except in the unit tests' host app: it would be taken from the user, and its
        // first access would write ⌥⌘N into their settings (same app identifier). Blocker (task 6.2, set aside):
        // lists read again or compiled in the background, except there too (the tests have their own store).
        if !TestEnvironment.isUnitTestHost() {
            miniWindows.start()
            if ContentBlockerService.isAvailable {
                ContentBlockerService.shared.start()
            }
        }
        // Extensions (task 6.3): mini windows are windows to them; installed extensions load in the background,
        // except with a test store (UI tests): never the user's.
        ExtensionManager.shared.windows.miniWindows = miniWindows
        if !session.isInMemory {
            ExtensionManager.shared.start()
        }
        // Links from other apps (task 8.2), including the one that launched the app.
        IncomingLinks.shared.handler = { [miniWindows] urls in
            miniWindows.openFromOtherApp(urls, destination: ExternalLinkDestination.current())
        }
        _session = State(initialValue: session)
        _miniWindows = State(initialValue: miniWindows)
    }

    var body: some Scene {
        // A single main window until sharing Spaces between windows is defined.
        Window(Text(verbatim: "Matcha"), id: Self.browserWindowID) {
            BrowserWindowView(session: session)
                .environment(miniWindows)
                .environment(DownloadManager.shared)
        }
        .windowStyle(.hiddenTitleBar)
        // Links from other apps go through the delegate (`IncomingLinks`): no window is created for them.
        .handlesExternalEvents(matching: [])
        .commands {
            BrowserCommands(miniWindows: miniWindows)
        }
        .onChange(of: appearance, initial: true) { appearance.apply() }

        // Private windows: each one has its own in-memory session, nothing is saved; never reopened at launch, like
        // in Safari.
        WindowGroup("Private Browsing", id: Self.privateWindowID) {
            PrivateWindowView()
                .environment(DownloadManager.shared)
        }
        .windowStyle(.hiddenTitleBar)
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
            SettingsView()
                .environment(session)
                .environment(miniWindows)
        }
    }
}
