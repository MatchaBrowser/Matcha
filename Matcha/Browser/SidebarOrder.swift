import Foundation

/// Order of the sidebar as seen by the keyboard (task 4.8): what it shows, from top to bottom. Favorites,
/// then pinned tabs (the content of a collapsed folder is not shown, so it is not included), then today tabs.
/// A split fits on one row, but its panes follow one another from left to right in `tabIDs`. Pure type.
nonisolated struct SidebarOrder: Equatable, Sendable {
    /// A favorite tile or a row: a tab, or the panes of a split from left to right.
    typealias Item = [UUID]

    /// ⌘1 to ⌘8.
    static let numberedShortcuts = 1 ... 8

    /// Favorite tiles, then visible pinned rows: those numbered by ⌘1 to ⌘8.
    let numbered: [Item]
    /// Rows of today tabs.
    let today: [Item]
    /// All the placed tabs, visible or not: locates a selected tab hidden in a collapsed folder.
    private let allTabIDs: [UUID]

    init(_ layout: SidebarLayout) {
        numbered = layout.favorites.map { [$0] } + Self.items(of: layout.pinnedRows(layout.pinned), in: layout)
        today = Self.items(of: layout.todayRows, in: layout)
        allTabIDs = layout.orderedTabIDs
    }

    /// Visible tabs, from top to bottom; the panes of a split one after the other.
    var tabIDs: [UUID] {
        (numbered + today).flatMap(\.self)
    }

    /// ⌘1 to ⌘8: the tile or row number `number` (starting at 1) of the favorites then the pinned tabs; nil beyond
    /// (today tabs are never numbered).
    func numberedItem(_ number: Int) -> Item? {
        guard Self.numberedShortcuts.contains(number), number <= numbered.count else {
            return nil
        }
        return numbered[number - 1]
    }

    /// ⌘9: the last row of the sidebar (today tabs, otherwise pinned tabs, otherwise favorites).
    var lastItem: Item? {
        today.last ?? numbered.last
    }

    /// ⌃⇥ (`forward`) and ⌃⇧⇥: the visible tab that follows (or precedes) `current`, wrapping to the start after
    /// the last one (and to the end before the first). In a split, the neighboring pane comes first. With no selected
    /// tab: the first (or the last). Nil if there is no other visible tab.
    func tab(after current: UUID?, forward: Bool) -> UUID? {
        let visible = tabIDs
        guard let current, let position = allTabIDs.firstIndex(of: current) else {
            return forward ? visible.first : visible.last
        }
        // Walks the full order: a hidden tab (collapsed folder) leads to its visible neighbor.
        let shown = Set(visible)
        let count = allTabIDs.count
        for step in 1 ..< count {
            let index = (position + (forward ? step : count - step)) % count
            if shown.contains(allTabIDs[index]) {
                return allTabIDs[index]
            }
        }
        return nil
    }

    /// One entry per row: the tab or the panes of the split; an expanded folder gives its own rows,
    /// one after the other, and a collapsed folder none.
    private static func items(of rows: [SidebarRow], in layout: SidebarLayout) -> [Item] {
        rows.flatMap { row -> [Item] in
            switch row {
            case let .tab(id, _): [[id]]
            case let .split(group, _): [group.tabIDs]
            case let .folder(folder, _): folder.isCollapsed ? [] : items(of: layout.pinnedRows(folder.items), in: layout)
            }
        }
    }
}
