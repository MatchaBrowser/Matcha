import AppKit
import Foundation

/// Lecture de l'état des fenêtres et des onglets (tâche 6.3), sous le suivi du framework Observation.
extension ExtensionWindows {
    /// État pur, et les objets vivants qu'il désigne.
    struct Snapshot {
        var state = ExtensionBrowserState()
        var tabs: [UUID: LiveTab] = [:]
        var windows: [UUID: ExtensionWindowOwner] = [:]
        /// Fenêtre clé de l'app, puis celle qui la porte : une feuille (alerte) ou une bulle (popup d'une extension)
        /// laissent active la fenêtre sur laquelle elles s'ouvrent ; une fenêtre de connexion, fenêtre enfant, l'est
        /// elle-même.
        let keyWindows: [NSWindow] = [NSApp.keyWindow, NSApp.keyWindow?.sheetParent, NSApp.keyWindow?.parent].compactMap(\.self)
        /// Rang dans `keyWindows` de la fenêtre active retenue.
        private var focusRank = Int.max

        /// Ajoute `tab` à la fenêtre en cours de lecture ; un onglet déjà vu ailleurs est ignoré.
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

        /// Ajoute une fenêtre ; elle est la fenêtre active si sa `NSWindow` est la fenêtre clé, ou porte celle-ci.
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
        for entry in browserWindows {
            guard let model = entry.model else {
                continue
            }
            addBrowserWindow(entry, model: model, to: &snapshot)
            sessions.append(model.session)
        }
        if let miniWindows {
            // Lu pour être prévenu quand la mini-fenêtre active change.
            _ = miniWindows.keyWindowID
            for controller in miniWindows.windows {
                var tabIDs: [UUID] = []
                snapshot.add(controller.tab, owner: .miniWindow(controller, miniWindows), isPinned: false, to: &tabIDs)
                addSinglePageWindow(id: controller.id, tabIDs: tabIDs, owner: .miniWindow(controller), to: &snapshot)
            }
            sessions.append(miniWindows.session)
        }
        var seen = Set<ObjectIdentifier>()
        for session in sessions where seen.insert(ObjectIdentifier(session.popupWindows)).inserted {
            let manager = session.popupWindows
            for controller in manager.windows {
                var tabIDs: [UUID] = []
                snapshot.add(controller.tab, owner: .popupWindow(controller, manager), isPinned: false, to: &tabIDs)
                addSinglePageWindow(id: controller.id, tabIDs: tabIDs, owner: .popupWindow(controller, manager), to: &snapshot)
            }
        }
        return snapshot
    }

    /// Fenêtre de navigation : les onglets de chaque Space, dans l'ordre des Spaces puis de la barre. Les favoris d'un
    /// profil, communs à ses Spaces, n'apparaissent qu'une fois, au début du premier Space de ce profil, pris dans le
    /// Space qui les tient (le dernier affiché de ce profil : les autres n'en ont qu'une copie jusqu'à leur affichage).
    /// L'aperçu ouvert suit son onglet d'origine.
    private func addBrowserWindow(_ entry: BrowserWindowEntry, model: WindowModel, to snapshot: inout Snapshot) {
        let session = model.session
        let displayed = model.space
        entry.favoriteHolders[displayed.record.profile?.id] = displayed.id
        var tabIDs: [UUID] = []
        var profilesSeen = Set<UUID?>()
        for space in session.spaces {
            let profileID = space.record.profile?.id
            if profilesSeen.insert(profileID).inserted {
                let holder = session.spaces.first { $0.id == entry.favoriteHolders[profileID] } ?? space
                for tab in holder.tabManager.favoriteTabs {
                    snapshot.add(tab, owner: .space(holder, model), isPinned: true, to: &tabIDs)
                }
            }
            let layout = space.tabManager.layout
            let favorites = Set(layout.favorites)
            for id in layout.orderedTabIDs where !favorites.contains(id) {
                if let tab = space.tabManager.tab(withID: id) {
                    snapshot.add(tab, owner: .space(space, model), isPinned: layout.place(of: id) == .pinned, to: &tabIDs)
                }
            }
        }
        let manager = displayed.tabManager
        var selected = Set(manager.displayedTabIDs).intersection(tabIDs)
        var active = manager.selectedTabID.flatMap { selected.contains($0) ? $0 : nil }
        // L'aperçu est la page au premier plan : un onglet juste après son onglet d'origine, actif tant qu'il est ouvert
        // (sans quoi ses scripts de contenu ne pourraient pas parler à leur extension : « Tab not found »).
        if let peek = manager.peek {
            var peekIDs: [UUID] = []
            snapshot.add(peek.tab, owner: .peek(displayed, model), isPinned: false, to: &peekIDs)
            tabIDs.insert(contentsOf: peekIDs, at: tabIDs.firstIndex(of: peek.sourceTabID).map { $0 + 1 } ?? tabIDs.count)
            selected.formUnion(peekIDs)
            active = peekIDs.first ?? active
        }
        let window = ExtensionBrowserState.Window(id: entry.id, tabIDs: tabIDs, activeTabID: active, selectedTabIDs: selected)
        snapshot.addWindow(window, owner: .browser(model, entry.window))
    }

    /// Mini-fenêtre ou fenêtre de connexion : sa page est l'onglet actif et sélectionné.
    private func addSinglePageWindow(id: UUID, tabIDs: [UUID], owner: ExtensionWindowOwner, to snapshot: inout Snapshot) {
        let window = ExtensionBrowserState.Window(id: id, tabIDs: tabIDs, activeTabID: tabIDs.first, selectedTabIDs: Set(tabIDs))
        snapshot.addWindow(window, owner: owner)
    }
}
