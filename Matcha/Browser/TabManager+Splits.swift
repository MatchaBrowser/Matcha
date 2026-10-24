import Foundation
import OSLog

/// Split view: tabs shown side by side. The active pane is the selected tab.
extension TabManager {
    /// Displayed by the active viewer (`TabManager+Selection`).
    var displayedTabIDs: [BrowserTab.ID] {
        activeViewer.displayedTabIDs
    }

    /// Tabs shown in the card, from left to right: the selected tab's split, otherwise the tab alone.
    var displayedTabs: [BrowserTab] {
        displayedTabs(in: activeViewer)
    }

    /// Displayed split: the selected tab's.
    var displayedSplit: SplitGroup? {
        displayedSplit(in: activeViewer)
    }

    func split(containing tab: BrowserTab) -> SplitGroup? {
        layout.split(containing: tab.id)
    }

    /// `.unavailable` for a tab of another manager; otherwise against the selected tab.
    func splitAvailability(for tabID: BrowserTab.ID) -> SplitAvailability {
        guard tab(withID: tabID) != nil else {
            return .unavailable
        }
        return layout.splitAvailability(of: tabID, anchor: selectedTabID)
    }

    /// “Open in Split View”: to the right of the active pane.
    @discardableResult
    func openInSplit(_ tab: BrowserTab) -> Bool {
        let active = selectedTabID.flatMap { displayedTabIDs.firstIndex(of: $0) } ?? 0
        return openInSplit(tab, at: active + 1)
    }

    /// At position `paneIndex` among the displayed panes; the tab becomes the active pane. False if refused.
    @discardableResult
    func openInSplit(_ tab: BrowserTab, at paneIndex: Int) -> Bool {
        guard let selected = selectedTabID, splitAvailability(for: tab.id) == .allowed else {
            return false
        }
        var joined: UUID?
        changingPlaces(of: [tab.id] + displayedTabIDs) { joined = $0.joinSplit(tab.id, anchor: selected, at: paneIndex) }
        guard joined != nil else {
            return false
        }
        setSelection(tab.id)
        let count = displayedTabIDs.count
        Logger.browser.info("Split: \(count, privacy: .public) panes")
        return true
    }

    /// “Remove from Split View”: the tab stays open, right after the split.
    func removeFromSplit(_ tab: BrowserTab) {
        keepingPanesOnScreen(leaving: tab) {
            updateLayout { $0.removeFromSplit(tab.id) }
        }
    }

    /// “Separate Tabs”: the tabs keep their place; the selection does not change.
    func separateSplit(_ groupID: UUID) {
        updateLayout { $0.separateSplit(groupID) }
    }

    /// Today split: its tabs are closed; pinned: they unload and the split remains.
    /// The selection moves out of the split.
    func closeSplit(_ groupID: UUID) {
        guard let group = layout.split(withID: groupID), let first = group.tabIDs.first else {
            return
        }
        let members = group.tabIDs.compactMap(tab(withID:))
        if layout.place(of: first) == .pinned {
            moveSelection(awayFrom: Set(group.tabIDs)) {
                members.forEach { $0.unload(resettingTo: $0.pinnedURL, title: $0.pinnedTitle) }
            }
        } else {
            moveSelection(awayFrom: Set(group.tabIDs)) { members.forEach(discard) }
        }
        Logger.browser.info("Split closed: \(members.count, privacy: .public) panes")
    }

    /// Moves the whole split (drag and drop of its row).
    func moveSplit(_ groupID: UUID, to destination: SidebarDestination) {
        guard let group = layout.split(withID: groupID) else {
            return
        }
        changingPlaces(of: group.tabIDs) { $0.moveSplit(groupID, to: destination) }
    }

    /// “Pin Split View” and “Unpin Split View”.
    func setSplitPlace(_ groupID: UUID, to place: TabPlace) {
        guard let group = layout.split(withID: groupID) else {
            return
        }
        changingPlaces(of: group.tabIDs) { $0.setSplitPlace(groupID, to: place) }
    }

    /// Width shares of the panes, kept at the end of a divider drag.
    func setSplitFractions(_ groupID: UUID, _ fractions: [Double]) {
        updateLayout { $0.setSplitFractions(groupID, fractions) }
    }

    /// A tab of the split is loaded, or asleep (task 5.6): the split can be closed.
    func hasLoadedTab(inSplit groupID: UUID) -> Bool {
        layout.split(withID: groupID)?.tabIDs.contains { tab(withID: $0)?.appearsLoaded == true } ?? false
    }

    /// Applies `change`; if `tab`, the active pane of a window, has left its split, its neighbor becomes active
    /// there: the rest of the split stays displayed.
    func keepingPanesOnScreen(leaving tab: BrowserTab, during change: () -> Void) {
        let neighbor = layout.split(containing: tab.id)?.neighbor(of: tab.id)
        let selecting = viewers.filter { $0.selectedTabID == tab.id }
        change()
        guard let neighbor, layout.place(of: neighbor) != nil, layout.split(containing: neighbor)?.contains(tab.id) != true else {
            return
        }
        selecting.forEach { setSelection(neighbor, for: $0) }
    }

    /// Applies `change`, then updates the original address of the tabs of `ids` that changed place.
    private func changingPlaces(of ids: [UUID], _ change: (inout SidebarLayout) -> Void) {
        let previous = Dictionary(ids.map { ($0, layout.place(of: $0)) }) { first, _ in first }
        updateLayout(change)
        for id in ids {
            guard let tab = tab(withID: id), let before = previous[id], layout.place(of: id) != before else {
                continue
            }
            updatePinnedOrigin(of: tab, previousPlace: before)
        }
    }
}
