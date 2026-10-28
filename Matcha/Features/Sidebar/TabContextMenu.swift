import SwiftUI

/// Context menu of a tab in the sidebar (or of a segment of a split's row).
struct TabContextMenu: View {
    let tab: BrowserTab
    let tabManager: TabManager
    /// The tab's name is edited in its row (a pinned tab's); elsewhere (favorite tile, pane of a split, icon of the
    /// column), in an alert of the window (`TabRenameAlert`).
    var renamesInRow = false

    @Environment(WindowModel.self) private var windowModel: WindowModel?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let place = tabManager.place(of: tab)
        let group = tabManager.split(containing: tab)
        // A window of its own tabs has neither favorites, nor pinned tabs, nor folders.
        if windowModel?.windowTabs == nil {
            placeItems(place: place, group: group)
            if tabManager.canRename(tab) {
                renameItems
            }
        }
        moveItems
        Divider()
        SplitMenuItems(tab: tab, tabManager: tabManager)
        Button("Duplicate Tab") { tabManager.duplicate(tab) }
        Button("Copy Link") {
            if let url = tab.displayedURL {
                copyLink(url)
            }
        }
        .disabled(tab.displayedURL == nil)
        Divider()
        closeItems(place: place, group: group)
        // The tab's split stays whole.
        let kept = Set(group?.tabIDs ?? [tab.id])
        Button("Close Other Tabs") { tabManager.closeOtherTabs(than: tab) }
            .disabled(!tabManager.todayTabs.contains { !kept.contains($0.id) })
    }

    /// Favorites, pinned tabs, folders.
    @ViewBuilder
    private func placeItems(place: TabPlace?, group: SplitGroup?) -> some View {
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
    }

    /// Name of a pinned tab or a favorite (`TabManager+Names`); “Use Page Title” forgets it.
    @ViewBuilder private var renameItems: some View {
        if renamesInRow {
            Button("Rename") { tabManager.renamingTabID = tab.id }
        } else if let windowModel {
            Button("Rename…") { windowModel.showRenameAlert(for: tab) }
        }
        if tab.customTitle != nil {
            Button("Use Page Title") { tabManager.renameTab(tab, to: "") }
        }
    }

    /// To another Space (from a window of its own tabs: to any Space), or to a window of its own.
    @ViewBuilder private var moveItems: some View {
        if let windowModel {
            let targets = windowModel.session.spaces.filter { $0.tabManager !== windowModel.tabManager }
            if !targets.isEmpty {
                Menu("Move to Space") {
                    ForEach(targets) { space in
                        Button(space.record.name) { windowModel.move(tab, to: space) }
                    }
                }
            }
            if windowModel.canOpenInNewWindow {
                Button("Open in New Window") {
                    openWindow(id: MatchaApp.browserWindowID, value: windowModel.detachToNewWindow(tab))
                }
            }
        }
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
