import SwiftUI

/// Context menu of a tab in the sidebar (or of a segment of a split's row).
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
            // Pinning a member pins the whole split.
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
        // The tab's split stays whole.
        let kept = Set(group?.tabIDs ?? [tab.id])
        Button("Close Other Tabs") { tabManager.closeOtherTabs(than: tab) }
            .disabled(!tabManager.todayTabs.contains { !kept.contains($0.id) })
    }

    /// Close: a today tab disappears; a pinned tab or a favorite is unloaded, “Delete Tab” removes it from
    /// the sidebar; a pinned split closes entirely.
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
            Button("Delete Tab") { tabManager.delete(tab, reopenable: true) }
        } else {
            Button("Close Tab") { tabManager.close(tab) }
                .disabled(!tab.appearsLoaded)
            Button("Delete Tab") { tabManager.delete(tab, reopenable: true) }
        }
    }

    /// With the window's “URL Copied” confirmation, like ⇧⌘C.
    private func copyLink(_ url: URL) {
        if let windowModel {
            windowModel.copyLink(url)
        } else {
            TabLinkCopier.copy(url)
        }
    }
}
