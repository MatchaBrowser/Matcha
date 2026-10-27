import AppKit
import Foundation

/// Several windows (`DECISIONS.md`): each one shows a Space and has its own selected tab there (`TabViewer`), the
/// sidebar being the same. The Space's tab actions apply to the window in front; a tab selected in two windows is shown
/// by the last one that showed it, the other one offers to show it there (“Show Here”).
extension WindowModel {
    /// Tabs the window shows: its own (detached tab), otherwise those of the displayed Space.
    var tabManager: TabManager {
        windowTabs?.tabManager ?? space.tabManager
    }

    /// This window's viewer of its tabs: of its own, otherwise of the displayed Space.
    var viewer: TabViewer {
        windowTabs?.tabManager.activeViewer ?? viewer(in: space)
    }

    /// This window's viewer of `space`, made the first time the window shows it.
    func viewer(in space: SpaceSession) -> TabViewer {
        if let viewer = viewers[space.id], viewer.tabManager === space.tabManager {
            return viewer
        }
        // A closed window takes nothing more: its viewers are released.
        guard !isClosed else {
            return space.tabManager.activeViewer
        }
        let viewer = space.tabManager.makeViewer()
        viewers[space.id] = viewer
        return viewer
    }

    /// A window of its own tabs that has none left (last one closed, or dropped into another window): it closes.
    var hasNoOwnTabsLeft: Bool {
        windowTabs?.tabManager.tabs.isEmpty ?? false
    }

    /// Selected tab of this window.
    var selectedTab: BrowserTab? {
        tabManager.selectedTab(in: viewer)
    }

    /// Front page of this window: the peek if it shows it, otherwise the selected tab.
    var frontTab: BrowserTab? {
        tabManager.frontTab(in: viewer)
    }

    /// Closes the peek if this window shows it (command bar, other tab, other Space…).
    func closePeek() {
        let tabManager = tabManager
        if tabManager.peek(in: viewer) != nil {
            tabManager.closePeek()
        }
    }

    /// The tab actions of the displayed Space apply to this window (it comes to the front, or acts).
    func activate() {
        tabManager.activate(viewer)
    }

    // MARK: Life of the window

    /// The window is displayed: it shows its Space, whose tab actions apply to it.
    func windowDidAppear() {
        isOpen = true
        let tabManager = tabManager
        tabManager.activate(viewer)
        tabManager.setOnScreen(viewer, true)
    }

    /// The window comes to the front: its tabs receive the actions, its Space holds its profile's favorites.
    func windowDidBecomeKey() {
        activate()
        if windowTabs == nil {
            session.showFavorites(in: space)
        }
    }

    /// Follows `window` becoming the key window, as soon as it does: before the click that made it so is handled.
    func track(_ window: NSWindow?) {
        windowTabs?.bringWindowToFront = { [weak window] in
            if window?.isMiniaturized == true {
                window?.deminiaturize(nil)
            }
            window?.makeKeyAndOrderFront(nil)
        }
        windowTabs?.closeWindow = { [weak window] in
            window?.close()
        }
        keyObserver.map(NotificationCenter.default.removeObserver)
        keyObserver = window.map { window in
            NotificationCenter.default
                .addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.windowDidBecomeKey()
                    }
                }
        }
    }

    /// The window closes: the peek it shows closes (sound, process), its viewers are released. The last window of a
    /// Space leaves it its selection, for the next one.
    func windowDidClose() {
        closePeek()
        translationHost.cancelAll()
        // Its own tabs close with it (⇧⌘T in their Space brings them back).
        if let windowTabs {
            windowTabs.close(into: session.originSpace(of: windowTabs))
            session.removeWindowTabs(windowTabs)
        }
        keyObserver.map(NotificationCenter.default.removeObserver)
        keyObserver = nil
        isOpen = false
        isClosed = true
        for space in session.spaces {
            if let viewer = viewers[space.id], viewer.tabManager === space.tabManager {
                space.tabManager.releaseViewer(viewer)
            }
        }
        viewers = [:]
    }

    // MARK: Moving tabs between windows

    /// Shows the tab `id` of the displayed Space in this window, taking it from the window that showed it (new window
    /// of a detached tab).
    func showTab(withID id: UUID) {
        let tabManager = space.tabManager
        guard let tab = tabManager.tab(withID: id) else {
            return
        }
        tabManager.activate(viewer)
        tabManager.setSelection(id, for: viewer)
        TabActivation.focusPage(of: tab)
    }

    /// “Open in New Window”, tab dragged out of the window: the tab leaves the sidebar for a window of its own (Arc's
    /// “This Window”), which the returned state opens; this window shows the next tab, as if it was closed here. A
    /// favorite or a pinned tab stays in the sidebar: the new window gets a copy of it.
    func detachToNewWindow(_ tab: BrowserTab) -> BrowserWindowState {
        let source = tabManager
        let origin = windowTabs.flatMap(session.originSpace(of:)) ?? space
        let tabs = session.makeWindowTabs(from: origin)
        if source.place(of: tab) == .today, let moved = source.detach(tab) {
            tabs.take(moved)
        } else {
            tabs.takeCopy(of: tab)
        }
        return BrowserWindowState(spaceID: origin.id, windowTabsID: tabs.id, cascades: true)
    }
}

/// A browser window, as tab sleeping sees it (task 5.6).
extension WindowModel: TabDisplay {
    var visibleTabIDs: Set<UUID> {
        let viewer = viewer
        var ids = Set(viewer.displayedTabIDs)
        if let peek = tabManager.peek(in: viewer) {
            ids.insert(peek.sourceTabID)
        }
        return ids
    }
}
