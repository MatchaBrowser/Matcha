import AppKit
import Observation
import OSLog
import WebKit

/// Fenêtres et onglets vus par les extensions (tâche 6.3), et leurs changements donnés au contrôleur des extensions.
///
/// Correspondance (`DECISIONS.md`) :
/// - une fenêtre de navigation (principale ou privée) est une fenêtre « normal » ; ses onglets sont ceux de **tous** ses
///   Spaces, Space après Space, chacun dans l'ordre de la barre (favoris, épinglés, onglets du jour), comme des groupes
///   d'onglets ; les favoris d'un profil n'y sont qu'une fois. L'onglet actif est le panneau actif du Space affiché, les
///   onglets sélectionnés les panneaux de son split. Changer de Space change donc l'onglet actif, sans fermer d'onglet ;
/// - l'aperçu (Peek) ouvert est un onglet, juste après son onglet d'origine, et l'onglet actif : WebKit refuse les
///   messages des scripts de contenu d'une page qui n'est pas un onglet connu ;
/// - une mini-fenêtre ou une fenêtre de connexion est une fenêtre « popup » d'une seule page.
///
/// Tout passe par un état pur (`ExtensionBrowserState`) relu à chaque changement — framework Observation (Spaces,
/// rangement, sélection, titres, adresses…), notifications des fenêtres (fenêtre clé, fermeture) — et comparé au
/// précédent par `ExtensionEventPlanner`. Aucun appel à semer dans le reste du code.
@MainActor
final class ExtensionWindows {
    /// Un onglet vivant et ce qui le possède.
    struct LiveTab {
        let tab: BrowserTab
        let owner: ExtensionTabOwner
    }

    /// Une fenêtre de navigation suivie, avec le Space qui tient les favoris de chaque profil (le dernier affiché).
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

    /// Reçoit les événements : le contrôleur des extensions (une fausse version dans les tests).
    weak var sink: (any ExtensionEventSink)?
    /// Mini-fenêtres de l'app (tâche 4.5).
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
    private var isApplying = false
    private var observers: [any NSObjectProtocol] = []

    init(sink: (any ExtensionEventSink)? = nil) {
        self.sink = sink
    }

    // MARK: Fenêtres de navigation

    /// Une fenêtre de navigation s'affiche, ou sa `NSWindow` change.
    func windowDidAppear(_ model: WindowModel, window: NSWindow?) {
        if let entry = browserWindows.first(where: { $0.model === model }) {
            entry.window = window
        } else {
            browserWindows.append(BrowserWindowEntry(model: model, window: window))
        }
        setNeedsUpdate()
    }

    /// La fenêtre se ferme : elle et ses onglets disparaissent pour les extensions.
    func windowDidDisappear(_ model: WindowModel) {
        browserWindows.removeAll { $0.model === model || $0.model == nil }
        setNeedsUpdate()
    }

    // MARK: Lecture

    func liveTab(_ id: UUID) -> LiveTab? {
        liveTabs[id]
    }

    func owner(ofWindow id: UUID) -> ExtensionWindowOwner? {
        liveWindows[id]
    }

    func location(ofTab id: UUID) -> ExtensionBrowserState.Location? {
        locations[id]
    }

    /// Fenêtres, la fenêtre active d'abord (exigé par `openWindowsFor`).
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

    /// L'onglet `tab` s'il est vu par les extensions (rangé dans une fenêtre ouverte).
    func adapter(for tab: BrowserTab) -> ExtensionTab? {
        guard liveTabs[tab.id]?.tab === tab else {
            return nil
        }
        return tabAdapter(tab.id)
    }

    /// Fenêtre de navigation de `model`, si elle est suivie.
    func adapter(for model: WindowModel) -> ExtensionWindow? {
        browserWindows.first { $0.model === model }.flatMap { state.window(withID: $0.id) != nil ? windowAdapter($0.id) : nil }
    }

    /// Fenêtre d'extension `id` (créée à la première demande, puis toujours la même : WebKit reconnaît les fenêtres à
    /// leur objet).
    func windowAdapter(_ id: UUID) -> ExtensionWindow {
        if let adapter = windowAdapters[id] {
            return adapter
        }
        let owner = liveWindows[id]
        let adapter = ExtensionWindow(id: id, windows: self, type: owner?.windowType ?? .normal, isPrivate: owner?.isPrivate ?? false)
        windowAdapters[id] = adapter
        return adapter
    }

    /// Onglet d'extension `id` (même règle que les fenêtres).
    func tabAdapter(_ id: UUID) -> ExtensionTab {
        if let adapter = tabAdapters[id] {
            return adapter
        }
        let adapter = ExtensionTab(id: id, windows: self)
        adapter.windowID = locations[id]?.windowID
        tabAdapters[id] = adapter
        return adapter
    }

    // MARK: Mise à jour

    /// Relit l'état au prochain tour de la boucle principale (les changements d'un même tour sont regroupés).
    func setNeedsUpdate() {
        guard !isUpdateScheduled else {
            return
        }
        isUpdateScheduled = true
        Task { @MainActor [weak self] in
            self?.update()
        }
    }

    /// Relit l'état tout de suite et donne les événements au contrôleur ; suit ensuite ce qui a été lu.
    func update() {
        isUpdateScheduled = false
        guard !isApplying else {
            setNeedsUpdate()
            return
        }
        startObservingWindows()
        let snapshot = withObservationTracking {
            makeSnapshot()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.setNeedsUpdate()
            }
        }
        apply(snapshot)
    }

    private func apply(_ snapshot: Snapshot) {
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
        if let sink, sink.isListening {
            isApplying = true
            events.forEach { send($0, to: sink) }
            isApplying = false
        }
        // Les objets des onglets et fenêtres fermés sont oubliés après leurs événements.
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

    /// Fenêtre clé, ouverture et fermeture des fenêtres (mini-fenêtres et fenêtres de connexion comprises) : AppKit
    /// le dit par notifications, que le framework Observation ne voit pas.
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
