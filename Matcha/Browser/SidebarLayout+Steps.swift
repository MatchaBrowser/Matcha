import Foundation

nonisolated extension SidebarLayout {
    /// Moving a tab one step up (`offset` −1) or down (+1) in its own list, without dragging (audit H3: VoiceOver
    /// actions, ⌥⌘↑ and ⌥⌘↓ on a row that has keyboard focus); nil at the edge of the list.
    func stepDestination(of id: UUID, by offset: Int) -> SidebarDestination? {
        guard let (container, index) = container(of: id) else {
            return nil
        }
        let target = index + offset
        guard target >= 0, target < itemCount(in: container) else {
            return nil
        }
        // The rank is read before the move: one step down is “before the item after the next one”.
        return container.destination(at: offset > 0 ? target + 1 : target)
    }

    /// Moving a split one row up (`offset` −1) or down (+1) in its list (review IU18): over the neighboring row, a
    /// tab, a folder or a whole split; nil at the edge of the list. The destination is that of its first pane
    /// (`moveSplit`).
    func splitStepDestination(of groupID: UUID, by offset: Int) -> SidebarDestination? {
        guard let group = split(withID: groupID), let first = group.tabIDs.first, let last = group.tabIDs.last,
              let (home, firstIndex) = container(of: first), let lastIndex = container(of: last)?.index
        else {
            return nil
        }
        let ids = itemIDs(in: home)
        if offset < 0 {
            guard firstIndex > 0 else {
                return nil
            }
            return home.destination(at: rowBounds(of: ids[firstIndex - 1], at: firstIndex - 1).lowerBound)
        }
        guard lastIndex + 1 < ids.count else {
            return nil
        }
        // The rank is read before the move: after the last item of the next row.
        return home.destination(at: rowBounds(of: ids[lastIndex + 1], at: lastIndex + 1).upperBound + 1)
    }

    /// Ranks of the row that item `id` (at `index`) belongs to: its split's panes, or the item alone.
    private func rowBounds(of id: UUID, at index: Int) -> ClosedRange<Int> {
        guard let group = split(containing: id), let first = group.tabIDs.first, let last = group.tabIDs.last,
              let start = container(of: first)?.index, let end = container(of: last)?.index
        else {
            return index ... index
        }
        return start ... end
    }

    private func itemCount(in container: Container) -> Int {
        itemIDs(in: container).count
    }

    /// Identifiers of the items of `container`: tabs, and folders among the pinned tabs.
    private func itemIDs(in container: Container) -> [UUID] {
        switch container {
        case .favorites: favorites
        case .today: today
        case .pinned(folder: nil): pinned.map(\.id)
        case let .pinned(folder?): pinned.folder(folder)?.items.map(\.id) ?? []
        }
    }
}
