import Foundation
@testable import Matcha
import Testing

/// Sidebar order for ⌘1 to ⌘9, ⌃⇥ and ⌃⇧⇥ (task 4.8).
struct SidebarOrderTests {
    let ids = (0 ..< 12).map { _ in UUID() }
    let folder = UUID()
    let subfolder = UUID()

    /// Favorites `favorites`, pinned `pinned` and today tabs `today` (indices in `ids`), in this order.
    func layout(favorites: [Int] = [], pinned: [Int] = [], today: [Int] = []) -> SidebarLayout {
        var layout = SidebarLayout()
        favorites.forEach { layout.setPlace(ids[$0], to: .favorite) }
        pinned.forEach { layout.setPlace(ids[$0], to: .pinned) }
        today.forEach { layout.insertToday(ids[$0], at: layout.today.count) }
        return layout
    }

    /// Indices in `ids` of each tile or row.
    func items(_ items: [SidebarOrder.Item]) -> [[Int]] {
        items.map(indices)
    }

    func indices(_ tabIDs: [UUID]) -> [Int] {
        tabIDs.compactMap { ids.firstIndex(of: $0) }
    }

    func next(_ order: SidebarOrder, after index: Int?, forward: Bool = true) -> Int? {
        order.tab(after: index.map { ids[$0] }, forward: forward).flatMap { ids.firstIndex(of: $0) }
    }

    // MARK: ⌘1 to ⌘9

    @Test func `favorites then pinned are numbered, never today's tabs`() {
        let order = SidebarOrder(layout(favorites: [0, 1], pinned: [2, 3], today: [4, 5]))
        #expect(items(order.numbered) == [[0], [1], [2], [3]])
        #expect(order.numberedItem(1) == [ids[0]])
        #expect(order.numberedItem(3) == [ids[2]])
        #expect(order.numberedItem(4) == [ids[3]])
        #expect(order.numberedItem(5) == nil)
        #expect(order.numberedItem(0) == nil)
    }

    @Test func `only eight rows are numbered`() {
        let order = SidebarOrder(layout(favorites: [0, 1, 2, 3], pinned: [4, 5, 6, 7, 8, 9]))
        #expect(order.numbered.count == 10)
        #expect(order.numberedItem(8) == [ids[7]])
        #expect(order.numberedItem(9) == nil)
    }

    @Test func `the last row is today's last, else the last pinned, else the last favorite`() {
        #expect(SidebarOrder(layout(favorites: [0], pinned: [1, 2], today: [3, 4])).lastItem == [ids[4]])
        #expect(SidebarOrder(layout(favorites: [0], pinned: [1, 2])).lastItem == [ids[2]])
        #expect(SidebarOrder(layout(favorites: [0, 1])).lastItem == [ids[1]])
        #expect(SidebarOrder(SidebarLayout()).lastItem == nil)
        #expect(SidebarOrder(SidebarLayout()).numbered.isEmpty)
    }

    // MARK: ⌃⇥ and ⌃⇧⇥

    @Test func `next and previous follow the sidebar and wrap around`() {
        let order = SidebarOrder(layout(favorites: [0], pinned: [1], today: [2, 3]))
        #expect(indices(order.tabIDs) == [0, 1, 2, 3])
        #expect(next(order, after: 0) == 1)
        #expect(next(order, after: 1) == 2)
        #expect(next(order, after: 3) == 0)
        #expect(next(order, after: 0, forward: false) == 3)
        #expect(next(order, after: 2, forward: false) == 1)
    }

    @Test func `without selection, next is the first tab and previous the last`() {
        let order = SidebarOrder(layout(pinned: [0], today: [1, 2]))
        #expect(next(order, after: nil) == 0)
        #expect(next(order, after: nil, forward: false) == 2)
        // Unknown tab (already removed): same.
        #expect(next(order, after: 9) == 0)
    }

    @Test func `a lone tab or an empty sidebar has no neighbor`() {
        let lone = SidebarOrder(layout(today: [0]))
        #expect(next(lone, after: 0) == nil)
        #expect(next(lone, after: 0, forward: false) == nil)
        let empty = SidebarOrder(SidebarLayout())
        #expect(next(empty, after: nil) == nil)
        #expect(next(empty, after: nil, forward: false) == nil)
    }

    // MARK: Splits

    @Test func `a split is one numbered row but each pane is a step`() throws {
        var layout = layout(pinned: [0, 1, 2], today: [3, 4, 5])
        try #require(layout.joinSplit(ids[1], anchor: ids[0], at: 1) != nil)
        try #require(layout.joinSplit(ids[5], anchor: ids[4], at: 0) != nil)
        let order = SidebarOrder(layout)
        #expect(items(order.numbered) == [[0, 1], [2]])
        #expect(items(order.today) == [[3], [5, 4]])
        #expect(order.numberedItem(1) == [ids[0], ids[1]])
        #expect(order.lastItem == [ids[5], ids[4]])
        // Panes from left to right, then the next row.
        #expect(indices(order.tabIDs) == [0, 1, 2, 3, 5, 4])
        #expect(next(order, after: 0) == 1)
        #expect(next(order, after: 1) == 2)
        #expect(next(order, after: 3) == 5)
        #expect(next(order, after: 4) == 0)
        #expect(next(order, after: 0, forward: false) == 4)
        #expect(next(order, after: 4, forward: false) == 5)
    }

    // MARK: Folders

    /// Pinned: 0, folder `folder` [1, subfolder `subfolder` [2], 3], 4; today tab 5.
    func folderLayout() -> SidebarLayout {
        var layout = layout(pinned: [0, 4], today: [5])
        layout.addFolder(id: folder, named: "Dossier", at: 1)
        layout.addFolder(id: subfolder, named: "Sous-dossier", in: folder)
        for (tab, parent, index) in [(1, folder, 0), (2, subfolder, 0), (3, folder, 2)] {
            layout.setPlace(ids[tab], to: .pinned)
            layout.move(ids[tab], to: .pinned(folder: parent, index: index))
        }
        return layout
    }

    @Test func `open folders show their rows depth first`() {
        let order = SidebarOrder(folderLayout())
        #expect(items(order.numbered) == [[0], [1], [2], [3], [4]])
        #expect(indices(order.tabIDs) == [0, 1, 2, 3, 4, 5])
    }

    @Test func `collapsed folders hide their tabs from numbers and steps`() {
        var layout = folderLayout()
        layout.setFolderCollapsed(subfolder, true)
        #expect(items(SidebarOrder(layout).numbered) == [[0], [1], [3], [4]])
        #expect(next(SidebarOrder(layout), after: 1) == 3)

        layout.setFolderCollapsed(folder, true)
        let order = SidebarOrder(layout)
        #expect(items(order.numbered) == [[0], [4]])
        #expect(indices(order.tabIDs) == [0, 4, 5])
        #expect(next(order, after: 0) == 4)
        #expect(next(order, after: 4, forward: false) == 0)
    }

    @Test func `a selected tab hidden in a collapsed folder leads to its visible neighbors`() {
        var layout = folderLayout()
        layout.setFolderCollapsed(folder, true)
        let order = SidebarOrder(layout)
        #expect(next(order, after: 2) == 4)
        #expect(next(order, after: 2, forward: false) == 0)
    }

    @Test func `the last row is never hidden in a collapsed folder`() {
        var layout = SidebarLayout()
        layout.setPlace(ids[0], to: .pinned)
        layout.addFolder(id: folder, named: "Dossier")
        layout.setPlace(ids[1], to: .pinned)
        layout.move(ids[1], to: .pinned(folder: folder, index: 0))
        #expect(SidebarOrder(layout).lastItem == [ids[1]])
        layout.setFolderCollapsed(folder, true)
        #expect(SidebarOrder(layout).lastItem == [ids[0]])
    }
}
