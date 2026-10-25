import Foundation
@testable import Matcha
import Testing

struct SidebarLayoutTests {
    private let ids = (0 ..< 6).map { _ in UUID() }

    @Test func `starts empty`() {
        let layout = SidebarLayout()
        #expect(layout.orderedTabIDs.isEmpty)
        #expect(layout.place(of: ids[0]) == nil)
    }

    @Test func `insert today at index`() {
        var layout = SidebarLayout()
        layout.insertToday(ids[0], at: 0)
        layout.insertToday(ids[1], at: 0)
        layout.insertToday(ids[2], at: 1)
        layout.insertToday(ids[3], at: 99)
        layout.insertToday(ids[4], at: -5)
        #expect(layout.today == [ids[4], ids[1], ids[2], ids[0], ids[3]])
        #expect(layout.place(of: ids[2]) == .today)
    }

    @Test func `insert today moves a tab that was elsewhere`() {
        var layout = SidebarLayout()
        layout.insertToday(ids[0], at: 0)
        layout.setPlace(ids[0], to: .pinned)
        layout.insertToday(ids[0], at: 0)
        #expect(layout.pinned.isEmpty)
        #expect(layout.today == [ids[0]])
    }

    @Test func `set place appends favorites and pinned and puts today on top`() {
        var layout = SidebarLayout()
        for id in ids.prefix(5) {
            layout.insertToday(id, at: layout.today.count)
        }
        layout.setPlace(ids[0], to: .favorite)
        layout.setPlace(ids[1], to: .favorite)
        layout.setPlace(ids[2], to: .pinned)
        layout.setPlace(ids[3], to: .pinned)
        layout.setPlace(ids[1], to: .today)

        #expect(layout.favorites == [ids[0]])
        #expect(layout.pinned == [.tab(ids[2]), .tab(ids[3])])
        #expect(layout.today == [ids[1], ids[4]])
        #expect(layout.place(of: ids[0]) == .favorite)
        #expect(layout.place(of: ids[3]) == .pinned)
    }

    @Test func `set place to the current place keeps the order`() {
        var layout = SidebarLayout()
        layout.setPlace(ids[0], to: .pinned)
        layout.setPlace(ids[1], to: .pinned)
        layout.setPlace(ids[0], to: .pinned)
        #expect(layout.pinned == [.tab(ids[0]), .tab(ids[1])])
    }

    @Test func `ordered tabs go favorites then pinned then today`() {
        var layout = SidebarLayout()
        layout.insertToday(ids[0], at: 0)
        layout.setPlace(ids[1], to: .pinned)
        layout.setPlace(ids[2], to: .favorite)
        #expect(layout.orderedTabIDs == [ids[2], ids[1], ids[0]])
    }

    @Test func `remove takes the tab out of any place`() {
        var layout = SidebarLayout()
        layout.setPlace(ids[0], to: .favorite)
        layout.setPlace(ids[1], to: .pinned)
        layout.insertToday(ids[2], at: 0)
        for id in ids.prefix(3) {
            layout.remove(id)
        }
        #expect(layout == SidebarLayout())
    }

    @Test func `pinned folders expose and lose their tabs`() {
        let folder = PinnedFolder(
            id: UUID(),
            name: "Travail",
            items: [.tab(ids[0]), .folder(PinnedFolder(id: UUID(), name: "Sous", items: [.tab(ids[1])]))],
        )
        let items: [PinnedItem] = [.tab(ids[2]), .folder(folder)]
        #expect(items.flatMap(\.tabIDs) == [ids[2], ids[0], ids[1]])

        let withoutNested = items.removingTab(ids[1])
        #expect(withoutNested.flatMap(\.tabIDs) == [ids[2], ids[0]])
        #expect(withoutNested.count == 2)
    }

    // MARK: Drag and drop

    /// Four today tabs, in the order 0, 1, 2, 3.
    private func todayLayout() -> SidebarLayout {
        var layout = SidebarLayout()
        for id in ids.prefix(4) {
            layout.insertToday(id, at: layout.today.count)
        }
        return layout
    }

    @Test(arguments: [
        (0, 3, [1, 2, 0, 3]),
        (3, 0, [3, 0, 1, 2]),
        (1, 2, [0, 1, 2, 3]),
        (1, 1, [0, 1, 2, 3]),
        (0, 4, [1, 2, 3, 0]),
        (2, 99, [0, 1, 3, 2]),
    ])
    func `move reorders today's tabs before the target row`(from: Int, before: Int, expected: [Int]) {
        var layout = todayLayout()
        layout.move(ids[from], to: .today(index: before))
        #expect(layout.today == expected.map { ids[$0] })
    }

    @Test func `move between sections`() {
        var layout = todayLayout()
        layout.move(ids[0], to: .favorites(index: 0))
        layout.move(ids[1], to: .favorites(index: 0))
        layout.move(ids[2], to: .pinned(folder: nil, index: 0))
        #expect(layout.favorites == [ids[1], ids[0]])
        #expect(layout.pinned == [.tab(ids[2])])
        #expect(layout.today == [ids[3]])

        layout.move(ids[1], to: .today(index: 1))
        #expect(layout.favorites == [ids[0]])
        #expect(layout.today == [ids[3], ids[1]])
        #expect(layout.place(of: ids[1]) == .today)
    }

    @Test func `move into a folder and reorder inside it`() throws {
        var layout = todayLayout()
        let folder = layout.addFolder(named: "Travail")
        layout.move(ids[0], to: .pinned(folder: folder, index: 0))
        layout.move(ids[1], to: .pinned(folder: folder, index: 99))
        layout.move(ids[1], to: .pinned(folder: folder, index: 0))
        let contents = try #require(layout.pinned.folder(folder))
        #expect(contents.items == [.tab(ids[1]), .tab(ids[0])])
        #expect(layout.place(of: ids[0]) == .pinned)
        #expect(layout.orderedTabIDs == [ids[1], ids[0], ids[2], ids[3]])

        layout.move(ids[0], to: .pinned(folder: nil, index: 0))
        #expect(layout.pinned.first == .tab(ids[0]))
        #expect(layout.pinned.folder(folder)?.items == [.tab(ids[1])])
    }

    @Test func `move into a nested folder`() {
        var layout = todayLayout()
        let parent = layout.addFolder(named: "Projets")
        let child = layout.addFolder(named: "Client", in: parent)
        layout.move(ids[2], to: .pinned(folder: child, index: 0))
        #expect(layout.pinned.location(of: ids[2])?.parent == child)
        #expect(layout.pinned.location(of: child)?.parent == parent)
    }

    @Test func `move to an unknown folder appends to pinned`() {
        var layout = todayLayout()
        layout.move(ids[0], to: .pinned(folder: UUID(), index: 0))
        #expect(layout.pinned == [.tab(ids[0])])
    }

    @Test func `move ignores a tab that is not in the sidebar`() {
        var layout = todayLayout()
        let before = layout
        layout.move(UUID(), to: .favorites(index: 0))
        #expect(layout == before)
    }

    @Test func `add folder at an index`() throws {
        var layout = SidebarLayout()
        layout.setPlace(ids[0], to: .pinned)
        let folder = layout.addFolder(named: "Lectures", at: 0)
        let first = try #require(layout.pinned.first)
        #expect(first.id == folder)
        #expect(layout.pinned.folder(folder)?.name == "Lectures")
    }

    // MARK: Folders

    @Test func `rename and collapse a nested folder`() {
        var layout = SidebarLayout()
        let parent = layout.addFolder(named: "Projets")
        let child = layout.addFolder(named: "Client", in: parent)
        layout.renameFolder(child, to: "Client A")
        layout.setFolderCollapsed(child, true)
        #expect(layout.pinned.folder(child)?.name == "Client A")
        #expect(layout.pinned.folder(child)?.isCollapsed == true)
        #expect(layout.pinned.folder(parent)?.isCollapsed == false)
    }

    @Test func `move a folder into another one and back`() {
        var layout = SidebarLayout()
        let first = layout.addFolder(named: "Un")
        let second = layout.addFolder(named: "Deux")
        layout.setPlace(ids[0], to: .pinned)

        layout.moveFolder(second, to: .pinned(folder: first, index: 0))
        #expect(layout.pinned.location(of: second)?.parent == first)
        #expect(layout.pinned.map(\.id) == [first, ids[0]])

        layout.moveFolder(second, to: .pinned(folder: nil, index: 99))
        #expect(layout.pinned.map(\.id) == [first, ids[0], second])
    }

    @Test func `reorder folders at the same level`() {
        var layout = SidebarLayout()
        let first = layout.addFolder(named: "Un")
        let second = layout.addFolder(named: "Deux")
        let third = layout.addFolder(named: "Trois")
        layout.moveFolder(first, to: .pinned(folder: nil, index: 2))
        #expect(layout.pinned.map(\.id) == [second, first, third])
    }

    @Test func `a folder cannot go into itself or its descendants`() {
        var layout = SidebarLayout()
        let parent = layout.addFolder(named: "Parent")
        let child = layout.addFolder(named: "Enfant", in: parent)
        let before = layout
        layout.moveFolder(parent, to: .pinned(folder: parent, index: 0))
        layout.moveFolder(parent, to: .pinned(folder: child, index: 0))
        #expect(layout == before)
    }

    @Test func `folders only go to pinned`() {
        var layout = SidebarLayout()
        let folder = layout.addFolder(named: "Dossier")
        let before = layout
        layout.moveFolder(folder, to: .favorites(index: 0))
        layout.moveFolder(folder, to: .today(index: 0))
        #expect(layout == before)
    }

    @Test func `removing a folder keeps its contents in place`() {
        var layout = SidebarLayout()
        layout.setPlace(ids[0], to: .pinned)
        let folder = layout.addFolder(named: "Dossier")
        layout.setPlace(ids[3], to: .pinned)
        let child = layout.addFolder(named: "Sous-dossier", in: folder)
        layout.insertToday(ids[1], at: 0)
        layout.insertToday(ids[2], at: 0)
        layout.move(ids[1], to: .pinned(folder: folder, index: 0))
        layout.move(ids[2], to: .pinned(folder: child, index: 0))

        layout.removeFolder(folder)
        #expect(layout.pinned.map(\.id) == [ids[0], ids[1], child, ids[3]])
        #expect(layout.pinned.folder(child)?.items == [.tab(ids[2])])
        #expect(layout.orderedTabIDs == [ids[0], ids[1], ids[2], ids[3]])
    }

    /// Review CO2: where a new today tab goes, and the tab shown once the selected one leaves, without `TabManager`.
    @Test func `insertion after an anchor and the next selection`() {
        var layout = SidebarLayout()
        (0 ..< 4).forEach { layout.insertToday(ids[$0], at: layout.today.count) }
        #expect(layout.todayInsertionIndex(after: ids[1]) { $0 == ids[2] } == 3)
        #expect(layout.todayInsertionIndex(after: ids[1]) { _ in false } == 2)
        #expect(layout.todayInsertionIndex(after: nil) { _ in true } == 0)

        let today = layout.today
        layout.remove(ids[1])
        #expect(layout.nextSelection(from: 1, in: today, leaving: [ids[1]], preferring: nil) == ids[2])
        #expect(layout.nextSelection(from: 1, in: today, leaving: [ids[1]], preferring: ids[3]) == ids[3])
        #expect(layout.nextSelection(from: nil, in: today, leaving: [ids[1]], preferring: nil) == nil)
        layout.remove(ids[2])
        layout.remove(ids[3])
        #expect(layout.nextSelection(from: 3, in: today, leaving: [ids[3]], preferring: nil) == ids[0])
    }
}
