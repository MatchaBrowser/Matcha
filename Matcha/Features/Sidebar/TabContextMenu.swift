import SwiftUI

/// Menu contextuel d'un onglet de la barre latérale (ou d'un morceau de la ligne d'un split).
struct TabContextMenu: View {
    let tab: BrowserTab
    let tabManager: TabManager

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    var body: some View {
        let place = tabManager.place(of: tab)
        let group = tabManager.split(containing: tab)
        if place == .favorite {
            Button("Remove from Favorites") { tabManager.setPlace(tab, to: .today) }
        } else {
            Button("Add to Favorites") { tabManager.setPlace(tab, to: .favorite) }
        }
        if let group {
            // Épingler un membre épingle tout le split.
            if place == .pinned {
                Button("Unpin Split View") { tabManager.setSplitPlace(group.id, to: .today) }
                Button("New Folder") { tabManager.newFolder() }
            } else {
                Button("Pin Split View") { tabManager.setSplitPlace(group.id, to: .pinned) }
            }
        } else if place == .pinned {
            Button("Unpin Tab") { tabManager.setPlace(tab, to: .today) }
            Button("New Folder") { tabManager.newFolder() }
        } else {
            Button("Pin Tab") { tabManager.setPlace(tab, to: .pinned) }
        }
        if let windowModel, windowModel.session.spaces.count > 1 {
            Menu("Move to Space") {
                ForEach(windowModel.session.spaces.filter { $0 !== windowModel.space }) { space in
                    Button(space.record.name) { windowModel.move(tab, to: space) }
                }
            }
        }
        Divider()
        SplitMenuItems(tab: tab, tabManager: tabManager)
        Button("Duplicate Tab") { tabManager.duplicate(tab) }
        Button("Copy Link") {
            if let url = tab.url {
                copyLink(url)
            }
        }
        .disabled(tab.url == nil)
        Divider()
        closeItems(place: place, group: group)
        // Le split de l'onglet reste entier.
        let kept = Set(group?.tabIDs ?? [tab.id])
        Button("Close Other Tabs") { tabManager.closeOtherTabs(than: tab) }
            .disabled(!tabManager.todayTabs.contains { !kept.contains($0.id) })
    }

    /// Fermer : un onglet du jour disparaît ; un épinglé ou un favori se décharge, « Supprimer » le retire de
    /// la barre ; un split épinglé se ferme en entier.
    @ViewBuilder
    private func closeItems(place: TabPlace?, group: SplitGroup?) -> some View {
        if place == .today {
            Button("Close Tab") { tabManager.close(tab) }
            if let group {
                Button("Close Split View") { tabManager.closeSplit(group.id) }
            }
        } else if let group {
            Button("Close Split View") { tabManager.closeSplit(group.id) }
                .disabled(!tabManager.hasLoadedTab(inSplit: group.id))
            Button("Delete Tab") { tabManager.delete(tab) }
        } else {
            Button("Close Tab") { tabManager.close(tab) }
                .disabled(!tab.isLoaded)
            Button("Delete Tab") { tabManager.delete(tab) }
        }
    }

    /// Avec la confirmation « URL copiée » de la fenêtre, comme ⇧⌘C.
    private func copyLink(_ url: URL) {
        if let windowModel {
            windowModel.copyLink(url)
        } else {
            TabLinkCopier.copy(url)
        }
    }
}
