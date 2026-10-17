import SwiftUI

/// Menu contextuel d'un onglet de la barre latérale.
struct TabContextMenu: View {
    let tab: BrowserTab
    let tabManager: TabManager

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    var body: some View {
        let place = tabManager.place(of: tab)
        if place == .favorite {
            Button("Remove from Favorites") { tabManager.setPlace(tab, to: .today) }
        } else {
            Button("Add to Favorites") { tabManager.setPlace(tab, to: .favorite) }
        }
        if place == .pinned {
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
        Button("Duplicate Tab") { tabManager.duplicate(tab) }
        Button("Copy Link") {
            if let url = tab.url {
                copyLink(url)
            }
        }
        .disabled(tab.url == nil)
        Divider()
        if place == .today {
            Button("Close Tab") { tabManager.close(tab) }
        } else {
            // Épinglé ou favori : fermer le décharge, supprimer le retire de la barre.
            Button("Close Tab") { tabManager.close(tab) }
                .disabled(!tab.isLoaded)
            Button("Delete Tab") { tabManager.delete(tab) }
        }
        Button("Close Other Tabs") { tabManager.closeOtherTabs(than: tab) }
            .disabled(!tabManager.todayTabs.contains { $0 !== tab })
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
