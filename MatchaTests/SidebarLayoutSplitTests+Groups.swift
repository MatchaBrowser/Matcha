import Foundation
@testable import Matcha
import Testing

/// Splits déplacés, épinglés, séparés ; lignes de la barre.
extension SidebarLayoutSplitTests {
    @Test func `moving a group keeps it together`() throws {
        // Du jour : X (0), A (1), B (2), Y (3) ; split [A, B].
        var layout = todayLayout(4)
        let created = group([1, 2], in: &layout)
        let groupID = try #require(created)
        layout.moveSplit(groupID, to: .today(index: 3))
        #expect(today(layout) == [0, 1, 2, 3])
        layout.moveSplit(groupID, to: .today(index: 4))
        #expect(today(layout) == [0, 3, 1, 2])
        layout.moveSplit(groupID, to: .today(index: 0))
        #expect(today(layout) == [1, 2, 0, 3])
        // Sur sa propre ligne : rien ne change.
        layout.moveSplit(groupID, to: .today(index: 0))
        #expect(today(layout) == [1, 2, 0, 3])
        expectSplitInvariants(layout)

        let folder = layout.addFolder(named: "Travail")
        layout.moveSplit(groupID, to: .pinned(folder: folder, index: 0))
        expectSplitInvariants(layout)
        #expect(layout.pinned.folder(folder)?.items == [.tab(ids[1]), .tab(ids[2])])
        #expect(today(layout) == [0, 3])

        layout.moveSplit(groupID, to: .pinned(folder: UUID(), index: 0))
        expectSplitInvariants(layout)
        #expect(layout.pinned.map(\.id) == [folder, ids[1], ids[2]])

        let before = layout
        layout.moveSplit(groupID, to: .favorites(index: 0))
        #expect(layout == before)
    }

    @Test func `pinning and unpinning a group`() throws {
        var layout = todayLayout(4)
        layout.setPlace(ids[0], to: .pinned)
        let created = group([2, 3], in: &layout)
        let groupID = try #require(created)
        layout.setSplitPlace(groupID, to: .pinned)
        expectSplitInvariants(layout)
        #expect(layout.pinned == [.tab(ids[0]), .tab(ids[2]), .tab(ids[3])])
        #expect(today(layout) == [1])

        let pinned = layout
        layout.setSplitPlace(groupID, to: .pinned)
        layout.setSplitPlace(groupID, to: .favorite)
        #expect(layout == pinned)

        layout.setSplitPlace(groupID, to: .today)
        expectSplitInvariants(layout)
        #expect(today(layout) == [2, 3, 1])
        #expect(layout.pinned == [.tab(ids[0])])
    }

    @Test func `deleting or moving a folder keeps its groups`() throws {
        var layout = todayLayout(3)
        layout.setPlace(ids[0], to: .pinned)
        let folder = layout.addFolder(named: "Travail")
        layout.move(ids[1], to: .pinned(folder: folder, index: 0))
        layout.move(ids[2], to: .pinned(folder: folder, index: 1))
        let created = group([1, 2], in: &layout)
        let groupID = try #require(created)
        layout.moveFolder(folder, to: .pinned(folder: nil, index: 0))
        expectSplitInvariants(layout)
        #expect(members(layout.split(withID: groupID)) == [1, 2])
        layout.removeFolder(folder)
        expectSplitInvariants(layout)
        #expect(layout.pinned == [.tab(ids[1]), .tab(ids[2]), .tab(ids[0])])
        #expect(members(layout.split(withID: groupID)) == [1, 2])
    }

    @Test func `separating keeps every tab in place`() throws {
        var layout = todayLayout(4)
        let created = group([1, 2, 3], in: &layout)
        let groupID = try #require(created)
        layout.separateSplit(groupID)
        #expect(layout.splits.isEmpty)
        #expect(today(layout) == [0, 1, 2, 3])
    }

    // MARK: Affichage

    @Test func `displayed tabs are the selected tab's group or the tab alone`() {
        var layout = todayLayout(4)
        group([1, 2], in: &layout)
        #expect(layout.displayedTabIDs(selected: nil).isEmpty)
        #expect(layout.displayedTabIDs(selected: ids[0]) == [ids[0]])
        #expect(layout.displayedTabIDs(selected: ids[2]) == [ids[1], ids[2]])
    }

    @Test func `rows show a group once at its first tab`() throws {
        var layout = todayLayout(7)
        let createdToday = group([1, 2], in: &layout)
        let todayGroup = try #require(createdToday)
        layout.setPlace(ids[4], to: .pinned)
        let folder = layout.addFolder(named: "Travail")
        layout.move(ids[5], to: .pinned(folder: folder, index: 0))
        layout.move(ids[6], to: .pinned(folder: folder, index: 1))
        let createdPinned = group([5, 6], in: &layout)
        let pinnedGroup = try #require(createdPinned)
        layout.setPlace(ids[3], to: .pinned)

        let splits = try (#require(layout.split(withID: todayGroup)), #require(layout.split(withID: pinnedGroup)))
        #expect(layout.todayRows == [.tab(ids[0], index: 0), .split(splits.0, index: 1)])
        let folderItem = try #require(layout.pinned.folder(folder))
        #expect(layout.pinnedRows(layout.pinned) == [.tab(ids[4], index: 0), .folder(folderItem, index: 1), .tab(ids[3], index: 2)])
        #expect(layout.pinnedRows(folderItem.items) == [.split(splits.1, index: 0)])
        #expect(layout.todayRows.map(\.id) == [ids[0], todayGroup])
    }
}
