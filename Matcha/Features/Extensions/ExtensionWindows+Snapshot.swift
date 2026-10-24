import AppKit
import Foundation

/// Reading of the state of the windows and tabs (task 6.3), under tracking by the Observation framework.
extension ExtensionWindows {
    /// Pure state, and the live objects it designates.
    struct Snapshot {
        var state = ExtensionBrowserState()
        var tabs: [UUID: LiveTab] = [:]
        var windows: [UUID: ExtensionWindowOwner] = [:]
        /// The app's key window, then the window that carries it: a sheet (alert) or a popover (an extension's popup)
        /// leaves the window it opens on active; a sign-in window, a child window, is itself active.
        let keyWindows: [NSWindow] = [NSApp.keyWindow, NSApp.keyWindow?.sheetParent, NSApp.keyWindow?.parent].compactMap(\.self)
        /// Index in `keyWindows` of the active window found so far.
        private var focusRank = Int.max

        /// Adds `tab` to the window being read; a tab already seen elsewhere is ignored.
        mutating func add(_ tab: BrowserTab, owner: ExtensionTabOwner, isPinned: Bool, to tabIDs: inout [UUID]) {
            guard tabs[tab.id] == nil else {
                return
            }
            tabs[tab.id] = LiveTab(tab: tab, owner: owner)
            tabIDs.append(tab.id)
            state.tabs[tab.id] = ExtensionBrowserState.Tab(
                title: tab.title,
                url: tab.url,
                isLoading: tab.isLoading,
                isPlayingAudio: tab.isPlayingAudio,
                isPinned: isPinned,
                zoomFactor: tab.pageZoom,
            )
        }

        /// Adds a window; it is the active window if its `NSWindow` is the key window, or carries it.
        mutating func addWindow(_ window: ExtensionBrowserState.Window, owner: ExtensionWindowOwner) {
            state.windows.append(window)
            windows[window.id] = owner
            if let nsWindow = owner.nsWindow, let rank = keyWindows.firstIndex(where: { $0 === nsWindow }), rank < focusRank {
                focusRank = rank
                state.focusedWindowID = window.id
            }
        }
    }

    func makeSnapshot() -> Snapshot {
        var snapshot = Snapshot()
        var sessions: [BrowserSession] = []
        let homes = tabHomes()
        for entry in browserWindows {
            guard let model = entry.model else {
                continue
            }
            addBrowserWindow(entry, model: model, homes: homes, to: &snapshot)
            sessions.append(model.session)
        }
        if let miniWindows {
            // Read to be notified when the active mini window changes.
            _ = miniWindows.keyWindowID
            for controller in miniWindows.windows {
                var tabIDs: [UUID] = []
                snapshot.add(controller.tab, owner: .miniWindow(controller, miniWindows), isPinned: false, to: &tabIDs)
                addSinglePageWindow(id: controller.id, tabIDs: tabIDs, owner: .miniWindow(controller), to: &snapshot)
            }
            sessions.append(miniWindows.session)
        }
        var seen = Set<ObjectIdentifier>()
        for session in sessions {
            guard let manager = session.popupWindows as? PopupWindowManager, seen.insert(ObjectIdentifier(manager)).inserted else {
                continue
            }
            for controller in manager.windows {
                var tabIDs: [UUID] = []
                snapshot.add(controller.tab, owner: .popupWindow(controller, manager), isPinned: false, to: &tabIDs)
                addSinglePageWindow(id: controller.id, tabIDs: tabIDs, owner: .popupWindow(controller, manager), to: &snapshot)
            }
        }
        return snapshot
    }

    /// Window of each tab shown by a browser window, when several show the same session: a tab belongs to one window
    /// only. The other tabs belong to the session's first window.
    private func tabHomes() -> [UUID: UUID] {
        var homes: [UUID: UUID] = [:]
        for entry in browserWindows {
            guard let model = entry.model else {
                continue
            }
            let viewer = model.viewer
            for id in viewer.displayedTabIDs where model.tabManager.shows(id, in: viewer) {
                homes[id] = entry.id
            }
        }
        return homes
    }

    /// Browser window: the tabs of each Space, in the order of the Spaces, then of the sidebar; with several windows on
    /// the same session, those it shows, and all the others for the first of them (`tabHomes`). A profile's favorites,
    /// shared by its Spaces, appear only once, at the start of the first Space of that profile, taken from the Space
    /// that holds them (the last displayed one of that profile: the others only have a copy of them until they are
    /// displayed). The open Peek follows its originating tab.
    private func addBrowserWindow(_ entry: BrowserWindowEntry, model: WindowModel, homes: [UUID: UUID], to snapshot: inout Snapshot) {
        // A window of its own tabs: only them.
        if model.windowTabs != nil {
            addWindowTabs(entry, model: model, to: &snapshot)
            return
        }
        let session = model.session
        let displayed = model.space
        entry.favoriteHolders[displayed.record.profile?.id] = displayed.id
        let firstWindow = browserWindows.first { $0.model?.session === session && $0.model?.windowTabs == nil }
        func belongs(_ tab: BrowserTab) -> Bool {
            homes[tab.id].map { $0 == entry.id } ?? (firstWindow === entry)
        }
        var tabIDs: [UUID] = []
        var profilesSeen = Set<UUID?>()
        for space in session.spaces {
            let profileID = space.record.profile?.id
            if profilesSeen.insert(profileID).inserted {
                let holder = session.spaces.first { $0.id == entry.favoriteHolders[profileID] } ?? space
                for tab in holder.tabManager.favoriteTabs where belongs(tab) {
                    snapshot.add(tab, owner: .space(holder, model), isPinned: true, to: &tabIDs)
                }
            }
            let layout = space.tabManager.layout
            let favorites = Set(layout.favorites)
            for id in layout.orderedTabIDs where !favorites.contains(id) {
                if let tab = space.tabManager.tab(withID: id), belongs(tab) {
                    snapshot.add(tab, owner: .space(space, model), isPinned: layout.place(of: id) == .pinned, to: &tabIDs)
                }
            }
        }
        addSelection(of: model, entry: entry, tabIDs: tabIDs, to: &snapshot)
    }

    /// Window of its own tabs (a detached tab): its tabs, in the sidebar's order.
    private func addWindowTabs(_ entry: BrowserWindowEntry, model: WindowModel, to snapshot: inout Snapshot) {
        var tabIDs: [UUID] = []
        for tab in model.tabManager.tabs {
            snapshot.add(tab, owner: .window(model), isPinned: false, to: &tabIDs)
        }
        addSelection(of: model, entry: entry, tabIDs: tabIDs, to: &snapshot)
    }

    /// Adds the window of `model` with its active and selected tabs: the panes it displays. Peek is the page in front:
    /// a tab right after its originating tab, active while it is open (otherwise its content scripts could not talk to
    /// their extension: “Tab not found”).
    private func addSelection(of model: WindowModel, entry: BrowserWindowEntry, tabIDs: [UUID], to snapshot: inout Snapshot) {
        var tabIDs = tabIDs
        let viewer = model.viewer
        var selected = Set(viewer.displayedTabIDs).intersection(tabIDs)
        var active = viewer.selectedTabID.flatMap { selected.contains($0) ? $0 : nil }
        if let peek = model.tabManager.peek(in: viewer) {
            var peekIDs: [UUID] = []
            snapshot.add(peek.tab, owner: .peek(model.space, model), isPinned: false, to: &peekIDs)
            tabIDs.insert(contentsOf: peekIDs, at: tabIDs.firstIndex(of: peek.sourceTabID).map { $0 + 1 } ?? tabIDs.count)
            selected.formUnion(peekIDs)
            active = peekIDs.first ?? active
        }
        let window = ExtensionBrowserState.Window(id: entry.id, tabIDs: tabIDs, activeTabID: active, selectedTabIDs: selected)
        snapshot.addWindow(window, owner: .browser(model, entry.window))
    }

    /// Mini window or sign-in window: its page is the active and selected tab.
    private func addSinglePageWindow(id: UUID, tabIDs: [UUID], owner: ExtensionWindowOwner, to snapshot: inout Snapshot) {
        let window = ExtensionBrowserState.Window(id: id, tabIDs: tabIDs, activeTabID: tabIDs.first, selectedTabIDs: Set(tabIDs))
        snapshot.addWindow(window, owner: owner)
    }
}
