import AppKit
import Observation
import OSLog
import WebKit

/// Windows and tabs seen by extensions (task 6.3), and their changes given to the extension controller.
///
/// Mapping (`DECISIONS.md`):
/// - a browser window (main or private) is a “normal” window; its tabs are those of **all** its Spaces, Space after
///   Space, each in the sidebar's order (favorites, pinned, Today tabs), like tab groups; a profile's favorites appear
///   in it only once. The active tab is the active pane of the displayed Space, the selected tabs are the panes of its
///   split. Switching Spaces therefore changes the active tab, without closing any tab;
/// - the open Peek is a tab, right after its originating tab, and the active tab: WebKit rejects the messages of the
///   content scripts of a page that is not a known tab;
/// - a mini window or a sign-in window is a single-page “popup” window.
///
/// Everything goes through a pure state (`ExtensionBrowserState`) read again at each change — Observation framework
/// (Spaces, arrangement, selection, titles, addresses…), window notifications (key window, closing) — and compared with
/// the previous one by `ExtensionEventPlanner`. No calls to scatter through the rest of the code.
@MainActor
final class ExtensionWindows {
    /// A live tab and what owns it.
    struct LiveTab {
        let tab: BrowserTab
        let owner: ExtensionTabOwner
    }

    /// A tracked browser window, with the Space that holds each profile's favorites (the last displayed one).
    final class BrowserWindowEntry {
        let id = UUID()
        weak var model: WindowModel?
        weak var window: NSWindow?
        var favoriteHolders: [UUID?: UUID] = [:]

        init(model: WindowModel, window: NSWindow?) {
            self.model = model
            self.window = window
        }
    }

    /// Receives the events: the extension controller (a fake version in the tests).
    weak var sink: (any ExtensionEventSink)?
    /// The app's mini windows (task 4.5).
    weak var miniWindows: MiniWindowManager? {
        didSet { setNeedsUpdate() }
    }

    private(set) var state = ExtensionBrowserState()
    private(set) var browserWindows: [BrowserWindowEntry] = []
    private var locations: [UUID: ExtensionBrowserState.Location] = [:]
    private var liveTabs: [UUID: LiveTab] = [:]
    private var liveWindows: [UUID: ExtensionWindowOwner] = [:]
    private var tabAdapters: [UUID: ExtensionTab] = [:]
    private var windowAdapters: [UUID: ExtensionWindow] = [:]
    private var isUpdateScheduled = false
    /// The state follows the windows (an extension listens, audit C5): without any, nothing is read nor compared.
    private var isTracking = false
    private var isApplying = false
    private var observers: [any NSObjectProtocol] = []

    init(sink: (any ExtensionEventSink)? = nil) {
        self.sink = sink
    }

    /// Windows that go away (tests) take their observers with them (audit C7).
    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Browser Windows

    /// A browser window is displayed, or its `NSWindow` changes.
    func windowDidAppear(_ model: WindowModel, window: NSWindow?) {
        if let entry = browserWindows.first(where: { $0.model === model }) {
            entry.window = window
        } else {
            browserWindows.append(BrowserWindowEntry(model: model, window: window))
        }
        setNeedsUpdate()
    }

    /// The window closes: it and its tabs disappear for extensions.
    func windowDidDisappear(_ model: WindowModel) {
        browserWindows.removeAll { $0.model === model || $0.model == nil }
        setNeedsUpdate()
    }

    // MARK: Reading

    func liveTab(_ id: UUID) -> LiveTab? {
        liveTabs[id]
    }

    func owner(ofWindow id: UUID) -> ExtensionWindowOwner? {
        liveWindows[id]
    }

    func location(ofTab id: UUID) -> ExtensionBrowserState.Location? {
        locations[id]
    }

    /// Windows, the active window first (required by `openWindowsFor`).
    var orderedWindows: [ExtensionWindow] {
        let ids = state.windows.map(\.id)
        let focused = state.focusedWindowID.map { [$0] } ?? []
        return (focused + ids.filter { $0 != state.focusedWindowID }).map(windowAdapter)
    }

    var focusedWindow: ExtensionWindow? {
        state.focusedWindowID.map(windowAdapter)
    }

    func tabs(inWindow id: UUID) -> [ExtensionTab] {
        (state.window(withID: id)?.tabIDs ?? []).filter { locations[$0]?.windowID == id }.map(tabAdapter)
    }

    func activeTab(inWindow id: UUID) -> ExtensionTab? {
        state.window(withID: id)?.activeTabID.map(tabAdapter)
    }

    func isSelected(_ tabID: UUID) -> Bool {
        guard let windowID = locations[tabID]?.windowID else {
            return false
        }
        return state.window(withID: windowID)?.selectedTabIDs.contains(tabID) ?? false
    }

    /// Tab `tab` if it is seen by extensions (in the sidebar of an open window).
    func adapter(for tab: BrowserTab) -> ExtensionTab? {
        guard liveTabs[tab.id]?.tab === tab else {
            return nil
        }
        return tabAdapter(tab.id)
    }

    /// Browser window of `model`, if it is tracked.
    func adapter(for model: WindowModel) -> ExtensionWindow? {
        browserWindows.first { $0.model === model }.flatMap { state.window(withID: $0.id) != nil ? windowAdapter($0.id) : nil }
    }

    /// Extension window `id` (created on the first request, then always the same: WebKit recognizes windows by their
    /// object).
    func windowAdapter(_ id: UUID) -> ExtensionWindow {
        if let adapter = windowAdapters[id] {
            return adapter
        }
        let owner = liveWindows[id]
        let adapter = ExtensionWindow(id: id, windows: self, type: owner?.windowType ?? .normal, isPrivate: owner?.isPrivate ?? false)
        windowAdapters[id] = adapter
        return adapter
    }

    /// Extension tab `id` (same rule as the windows).
    func tabAdapter(_ id: UUID) -> ExtensionTab {
        if let adapter = tabAdapters[id] {
            return adapter
        }
        let adapter = ExtensionTab(id: id, windows: self)
        adapter.windowID = locations[id]?.windowID
        tabAdapters[id] = adapter
        return adapter
    }

    // MARK: Update

    /// Reads the state again on the next turn of the main run loop (the changes of a single turn are grouped).
    func setNeedsUpdate() {
        guard !isUpdateScheduled, isTracking || sink?.isListening == true else {
            return
        }
        isUpdateScheduled = true
        Task { @MainActor [weak self] in
            self?.update()
        }
    }

    /// Reads the state again right away and gives the events to the controller; then tracks what was read. Without a
    /// listening extension, it stops following the windows. `beforeLoading`: an extension is about to load and WebKit
    /// will ask for the open windows; read without sending anything if nothing was followed.
    func update(beforeLoading: Bool = false) {
        isUpdateScheduled = false
        let isListening = sink?.isListening == true
        guard isListening || beforeLoading else {
            isTracking = false
            return
        }
        guard !isApplying else {
            setNeedsUpdate()
            return
        }
        startObservingWindows()
        // Before a first loading, the windows are read without events: the extension asks WebKit for them.
        let sendsEvents = isListening && (isTracking || !beforeLoading)
        isTracking = true
        let snapshot = withObservationTracking {
            makeSnapshot()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.setNeedsUpdate()
            }
        }
        apply(snapshot, sendsEvents: sendsEvents)
    }

    private func apply(_ snapshot: Snapshot, sendsEvents: Bool) {
        let events = ExtensionEventPlanner.events(from: state, to: snapshot.state)
        state = snapshot.state
        locations = state.locations()
        liveTabs = snapshot.tabs
        liveWindows = snapshot.windows
        for (id, adapter) in tabAdapters {
            if let windowID = locations[id]?.windowID {
                adapter.windowID = windowID
            }
        }
        guard !events.isEmpty else {
            return
        }
        if sendsEvents, let sink {
            isApplying = true
            events.forEach { send($0, to: sink) }
            isApplying = false
        }
        // The objects of closed tabs and windows are forgotten after their events.
        tabAdapters = tabAdapters.filter { locations[$0.key] != nil }
        windowAdapters = windowAdapters.filter { snapshot.windows[$0.key] != nil }
    }

    private func send(_ event: ExtensionEvent, to sink: any ExtensionEventSink) {
        switch event {
        case let .openWindow(id):
            sink.didOpenWindow(windowAdapter(id))
        case let .openTab(id):
            sink.didOpenTab(tabAdapter(id))
        case let .moveTab(id, fromIndex, oldWindowID):
            sink.didMoveTab(tabAdapter(id), from: fromIndex, in: windowAdapter(oldWindowID))
        case let .changeTab(id, changes):
            sink.didChangeTabProperties(WKWebExtension.TabChangedProperties(changes), for: tabAdapter(id))
        case let .activateTab(id, previousTabID):
            sink.didActivateTab(tabAdapter(id), previousActiveTab: previousTabID.map(tabAdapter))
        case let .selectTabs(ids):
            sink.didSelectTabs(ids.map(tabAdapter))
        case let .deselectTabs(ids):
            sink.didDeselectTabs(ids.map(tabAdapter))
        case let .closeTab(id, windowIsClosing):
            sink.didCloseTab(tabAdapter(id), windowIsClosing: windowIsClosing)
        case let .closeWindow(id):
            sink.didCloseWindow(windowAdapter(id))
        case let .focusWindow(id):
            sink.didFocusWindow(id.map(windowAdapter))
        }
    }

    /// Key window, opening and closing of windows (mini windows and sign-in windows included): AppKit reports them
    /// through notifications, which the Observation framework does not see.
    private func startObservingWindows() {
        guard observers.isEmpty else {
            return
        }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setNeedsUpdate()
                }
            }
        }
    }
}
