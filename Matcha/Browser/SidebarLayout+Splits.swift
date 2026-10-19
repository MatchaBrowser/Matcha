import Foundation

/// Split view: neighboring tabs shown side by side.
///
/// Rules (restored by `normalizeSplits` after each change): the members of a split follow each other
/// in a single container (today tabs, root of the pinned tabs or a folder), in pane order;
/// never a favorite; a tab in only one split; moving, pinning, favoriting or removing a tab takes it
/// out of its split, which is undone below two tabs.
nonisolated extension SidebarLayout {
    func split(containing tabID: UUID) -> SplitGroup? {
        splits.first { $0.contains(tabID) }
    }

    func split(withID id: UUID) -> SplitGroup? {
        splits.first { $0.id == id }
    }

    /// Tabs shown when `selected` is selected: its split from left to right, otherwise itself alone; [] if nil.
    func displayedTabIDs(selected: UUID?) -> [UUID] {
        guard let selected else {
            return []
        }
        return split(containing: selected)?.tabIDs ?? [selected]
    }

    /// `tabID` against what `anchor` displays: unavailable without an anchor, with itself, a favorite, an unplaced
    /// tab or a member of the displayed split; full at 4 panes; allowed otherwise.
    func splitAvailability(of tabID: UUID, anchor: UUID?) -> SplitAvailability {
        guard let anchor, anchor != tabID,
              let tabPlace = place(of: tabID), tabPlace != .favorite,
              let anchorPlace = place(of: anchor), anchorPlace != .favorite
        else {
            return .unavailable
        }
        let group = split(containing: anchor)
        if group?.contains(tabID) == true {
            return .unavailable
        }
        return group?.isFull == true ? .full : .allowed
    }

    /// `tabID` joins the split of `anchor` (created with `newGroupID` if needed) at position `paneIndex`; nil if
    /// refused. The split keeps the anchor's place, except a today split joined by a pinned tab: it goes to the
    /// pinned tab's place. If the tab was part of another split, it leaves it.
    @discardableResult
    mutating func joinSplit(_ tabID: UUID, anchor: UUID, at paneIndex: Int, newGroupID: UUID = UUID()) -> UUID? {
        guard splitAvailability(of: tabID, anchor: anchor) == .allowed else {
            return nil
        }
        var group = split(containing: anchor) ?? SplitGroup(id: newGroupID, tabIDs: [anchor])
        // A pinned tab is never unpinned unasked: a today split joined by a pinned tab goes to its place.
        let pinnedWins = place(of: anchor) == .today && place(of: tabID) == .pinned
        guard let start = container(of: pinnedWins ? tabID : group.tabIDs[0]) else {
            return nil
        }
        group.insert(tabID, at: paneIndex)
        let others = splits.filter { $0.id != group.id }.map { other in
            var other = other
            other.remove(tabID)
            return other
        }
        placeTab(group.tabIDs[0], at: start.container.destination(at: start.index))
        for (previous, id) in zip(group.tabIDs, group.tabIDs.dropFirst()) {
            placeTab(id, after: previous)
        }
        setSplits(others + [group])
        return group.id
    }

    /// The tab leaves its split and goes right after the last other member.
    mutating func removeFromSplit(_ tabID: UUID) {
        guard var group = split(containing: tabID), let last = group.tabIDs.last(where: { $0 != tabID }) else {
            return
        }
        group.remove(tabID)
        placeTab(tabID, after: last)
        setSplits(splits.map { $0.id == group.id ? group : $0 })
    }

    /// Undoes the split; its tabs keep their place.
    mutating func separateSplit(_ groupID: UUID) {
        setSplits(splits.filter { $0.id != groupID })
    }

    /// Moves the whole split (drag and drop), in pane order; refused toward the favorites.
    mutating func moveSplit(_ groupID: UUID, to destination: SidebarDestination) {
        guard let group = split(withID: groupID), let first = group.tabIDs.first, Container(destination) != .favorites else {
            return
        }
        // In the same container, `placeTab` corrects the rank: dropping the split on its own row changes nothing.
        placeTab(first, at: destination)
        for (previous, id) in zip(group.tabIDs, group.tabIDs.dropFirst()) {
            placeTab(id, after: previous)
        }
        setSplits(splits)
    }

    /// Pins (end of the pinned tabs' root) or unpins (top of the today tabs) the whole split; no effect if it is
    /// already there or toward the favorites.
    mutating func setSplitPlace(_ groupID: UUID, to place: TabPlace) {
        guard let first = split(withID: groupID)?.tabIDs.first, self.place(of: first) != place else {
            return
        }
        switch place {
        case .favorite: return
        case .pinned: moveSplit(groupID, to: .pinned(folder: nil, index: pinned.count))
        case .today: moveSplit(groupID, to: .today(index: 0))
        }
    }

    /// Width shares of the panes (normalized; invalid ones: equal shares).
    mutating func setSplitFractions(_ groupID: UUID, _ fractions: [Double]) {
        guard let index = splits.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        var groups = splits
        groups[index].setFractions(fractions)
        setSplits(groups)
    }
}
