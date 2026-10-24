import Foundation
import Observation
import WebKit

/// A Space's tabs, their arrangement in the sidebar, and the tab each window selected there (`TabManager+Selection`).
@MainActor
@Observable
final class TabManager {
    /// Place and order of the tabs in the sidebar, saved by the Space (`SpaceStore`).
    private(set) var layout = SidebarLayout()
    /// Viewer the tab actions apply to (selection, new tabs, Peek): that of the window in front showing this Space.
    /// The first one holds the restored selection until a window takes it.
    private(set) var activeViewer = TabViewer()
    /// The viewers of the windows that show or showed this Space, the active one included.
    @ObservationIgnored private(set) var viewers: [TabViewer] = []
    /// Which window shows each tab: the session's, shared by its Spaces; this manager's own otherwise (tests).
    @ObservationIgnored var displays = TabDisplayRegistry() {
        didSet { viewers.forEach(displays.register) }
    }

    /// Folder whose name is being edited in the sidebar (UI state).
    var renamingFolderID: UUID?
    /// Peek opened on top of the displayed pages (Shift-click, task 4.4): a page outside the sidebar.
    private(set) var peek: Peek?
    /// Tabs closed by the user, that ⇧⌘T brings back (audit H2); in memory only.
    var closedTabs = ClosedTabGroups()
    private var tabsByID: [BrowserTab.ID: BrowserTab] = [:]

    /// Data store (cookies, storage) of this window's tabs.
    @ObservationIgnored let websiteDataStore: WKWebsiteDataStore
    /// Delegate of all web views of this window (the views do not retain it).
    @ObservationIgnored let coordinator: NavigationCoordinator
    @ObservationIgnored let faviconService: FaviconService
    /// Configuration of new pages (source viewer, extensions).
    @ObservationIgnored let pages: WebConfigurationFactory
    /// Window these tabs' downloads belong to: a private window's scope forgets them.
    @ObservationIgnored let downloadScope: DownloadScope
    /// Permission decisions of these tabs' profile (task 5.2), given by the Space; nil: nothing is remembered.
    @ObservationIgnored var sitePermissions: SitePermissionScope?
    /// Page zoom per site (task 5.4), given by the Space: the session's; nil: nothing is remembered.
    @ObservationIgnored var siteZooms: SiteZoomStore?
    /// History of this Space's pages (task 5.5), given by the Space; nil: nothing is remembered (private window).
    @ObservationIgnored var history: HistoryScope?
    /// What is displayed in the session's windows (tasks 5.6 and 5.7), given by the session.
    @ObservationIgnored weak var lifecycle: TabLifecycleService?
    /// The session's sign-in windows (task 5.8), given by the session; nil (tests): tabs instead.
    @ObservationIgnored weak var popupWindows: (any PopupWindowHosting)?
    /// The session's blocker (task 6.2), given by the session; nil (tests): pages are not tracked.
    @ObservationIgnored var contentBlocking: ContentBlockerScope?

    /// `services`: the session's (audit C2); the tests' own by default, without extensions, downloads or windows.
    init(websiteDataStore: WKWebsiteDataStore, services: SessionServices = SessionServices(), downloadScope: DownloadScope = .regular) {
        self.websiteDataStore = websiteDataStore
        faviconService = services.favicons
        pages = services.pages
        coordinator = services.makeCoordinator()
        self.downloadScope = downloadScope
        coordinator.tabHost = self
        adopt(activeViewer)
    }

    /// All tabs, in sidebar order.
    var tabs: [BrowserTab] {
        layout.orderedTabIDs.compactMap { tabsByID[$0] }
    }

    var favoriteTabs: [BrowserTab] {
        layout.favorites.compactMap { tabsByID[$0] }
    }

    var todayTabs: [BrowserTab] {
        layout.today.compactMap { tabsByID[$0] }
    }

    var selectedTab: BrowserTab? {
        selectedTabID.flatMap { tabsByID[$0] }
    }

    func selectedTab(in viewer: TabViewer) -> BrowserTab? {
        viewer.selectedTabID.flatMap { tabsByID[$0] }
    }

    func tab(withID id: BrowserTab.ID) -> BrowserTab? {
        tabsByID[id]
    }

    /// Tab that owns `webView`.
    func tab(for webView: WKWebView) -> BrowserTab? {
        tabsByID.values.first { $0.webView === webView }
    }

    func place(of tab: BrowserTab) -> TabPlace? {
        layout.place(of: tab.id)
    }

    /// Opens a tab at the top of the today tabs and loads `url` in it if provided; `source`: the page whose link it is.
    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true, from source: URL? = nil) -> BrowserTab {
        let configuration = pages.makeConfiguration(websiteDataStore: websiteDataStore)
        let tab = insertTab(configuration: configuration, after: nil, select: select)
        if let url {
            tab.load(url, from: source)
        }
        return tab
    }

    /// Inserts among the today tabs a tab whose web view is created with `configuration`, as is:
    /// WebKit requires this for windows opened by a page.
    /// If `anchor` is a today tab, the new one goes after it and after the tabs already opened
    /// from it, to keep the order of clicks; otherwise, at the top.
    /// It is selected if `select` is true or if no tab is selected.
    @discardableResult
    func insertTab(configuration: WKWebViewConfiguration, after anchor: BrowserTab?, select: Bool) -> BrowserTab {
        let tab = BrowserTab(configuration: configuration, openerID: anchor?.id)
        insert(tab, after: anchor, select: select)
        return tab
    }

    /// Places among the today tabs an already created tab (Peek opened as a tab; task 4.5: “Open in Space”), like
    /// `insertTab`.
    func insert(_ tab: BrowserTab, after anchor: BrowserTab?, select: Bool) {
        tab.delegate = coordinator
        tab.makeWebViewIfNeeded()
        tabsByID[tab.id] = tab
        layout.insertToday(tab.id, at: todayInsertionIndex(after: anchor))
        if select || selectedTab == nil {
            setSelection(tab.id)
        }
    }

    /// Closes `tab` (⌘W, ×). A today tab goes away. A pinned tab or a favorite stays in the sidebar,
    /// as in Arc: it goes back to its original address and unloads; a pinned split closes as a whole.
    /// If it was selected, its neighbor in the split takes the selection, otherwise the next today tab, or the previous
    /// one; with none, or for a pinned tab or a favorite, the window shows its empty page (`moveSelection`).
    func close(_ tab: BrowserTab) {
        guard let place = layout.place(of: tab.id) else {
            return
        }
        if place == .today {
            delete(tab, reopenable: true)
        } else if place == .pinned, let group = layout.split(containing: tab.id) {
            // A pinned split closes as a whole, like a pinned tab: it unloads and stays in the sidebar.
            closeSplit(group.id)
        } else {
            moveSelection(awayFrom: tab) {
                tab.unload(resettingTo: tab.pinnedURL, title: tab.pinnedTitle)
            }
        }
    }

    /// Removes the tab from the sidebar, wherever it is, and releases its web view. `reopenable`: closed by the user,
    /// ⇧⌘T can bring it back (not a tab that moves to another Space).
    func delete(_ tab: BrowserTab, reopenable: Bool = false) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        if reopenable {
            rememberClosed([tab])
        }
        moveSelection(awayFrom: tab) { discard(tab) }
    }

    /// Selects the tab; an unloaded tab then reloads its page.
    func select(_ tab: BrowserTab) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        setSelection(tab.id)
    }

    /// Places the tab in the favorites, the pinned tabs (at the end) or the today tabs (at the top); it leaves
    /// its split, the rest of which stays displayed.
    func setPlace(_ tab: BrowserTab, to place: TabPlace) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        keepingPanesOnScreen(leaving: tab) {
            let previous = layout.place(of: tab.id)
            layout.setPlace(tab.id, to: place)
            updatePinnedOrigin(of: tab, previousPlace: previous)
        }
    }

    /// Moves the tab in the sidebar (drag and drop); it leaves its split, the rest of which stays displayed.
    func move(_ tab: BrowserTab, to destination: SidebarDestination) {
        guard tabsByID[tab.id] != nil else {
            return
        }
        keepingPanesOnScreen(leaving: tab) {
            let previous = layout.place(of: tab.id)
            layout.move(tab.id, to: destination)
            updatePinnedOrigin(of: tab, previousPlace: previous)
        }
    }

    // MARK: Primitives for extensions

    /// Adds an existing tab (restored or coming from another Space), attached to this Space's delegate.
    func register(_ tab: BrowserTab) {
        tab.delegate = coordinator
        tabsByID[tab.id] = tab
        // A tab restored without its page shows the icon of its website kept on disk, without waiting to be opened.
        if tab.favicon == nil, !tab.isLoaded {
            faviconService.showCachedIcon(on: tab, host: tab.url?.host())
        }
    }

    /// Forgets a tab without closing it (it keeps existing elsewhere).
    func unregister(_ id: BrowserTab.ID) {
        tabsByID[id] = nil
    }

    /// Selects `id` without loading its page (restoration).
    func restoreSelection(_ id: BrowserTab.ID?) {
        activeViewer.selectedTabID = id
    }

    /// Primitive of `TabManager+Selection`: makes `viewer` the active one.
    func setActiveViewer(_ viewer: TabViewer) {
        activeViewer = viewer
    }

    /// Primitive of `TabManager+Selection`: `viewer` now belongs to this Space.
    func adopt(_ viewer: TabViewer) {
        viewer.tabManager = self
        viewers.append(viewer)
        displays.register(viewer)
    }

    /// Primitive of `TabManager+Selection`: forgets `viewer` (never the active one).
    func forget(_ viewer: TabViewer) {
        viewers.removeAll { $0 === viewer }
    }

    /// Primitive of `TabManager+Peek`: replaces the Peek, without releasing anything.
    func setPeek(_ newPeek: Peek?) {
        peek = newPeek
    }

    /// The extensions' only entry point to modify the layout.
    func updateLayout(_ change: (inout SidebarLayout) -> Void) {
        change(&layout)
    }

    /// A tab that becomes pinned or a favorite keeps its current address and title as its origin;
    /// once a today tab again, it forgets them.
    func updatePinnedOrigin(of tab: BrowserTab, previousPlace: TabPlace?) {
        if layout.place(of: tab.id) == .today {
            tab.pinnedURL = nil
            tab.pinnedTitle = nil
        } else if previousPlace == .today || tab.pinnedURL == nil {
            tab.pinnedURL = tab.url
            tab.pinnedTitle = tab.title
        }
    }

    func discard(_ tab: BrowserTab) {
        layout.remove(tab.id)
        tabsByID[tab.id] = nil
        displays.forget(tab.id)
        tab.discard()
    }

    /// After the anchor (after its split if it has one) and the tabs already opened from it; at the top without a
    /// today anchor.
    private func todayInsertionIndex(after anchor: BrowserTab?) -> Int {
        guard let anchor, var index = layout.today.firstIndex(of: layout.split(containing: anchor.id)?.tabIDs.last ?? anchor.id) else {
            return 0
        }
        index += 1
        while index < layout.today.count, tabsByID[layout.today[index]]?.openerID == anchor.id {
            index += 1
        }
        return index
    }
}
