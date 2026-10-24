import Foundation
@testable import Matcha
import Testing

/// Drop on a sidebar row or a favorite tile, following the pointer: before, after, or into a folder.
struct SidebarRowDropTests {
    private let ids = (0 ..< 6).map { _ in UUID() }

    private func indices(_ items: [PinnedItem]) -> [Int] {
        items.compactMap { item in
            guard case let .tab(id) = item else {
                return nil
            }
            return ids.firstIndex(of: id)
        }
    }

    /// Row of `id` (tab or folder) among the pinned items of `parent`.
    private func row(_ id: UUID, in layout: SidebarLayout, parent: UUID? = nil) throws -> SidebarRow {
        let items = try parent.map { try #require(layout.pinned.folder($0)).items } ?? layout.pinned
        return try #require(layout.pinnedRows(items).first { $0.id == id })
    }

    /// Drops the tab `index` on `part` of `row`, as the row would.
    private func drop(_ index: Int, on part: SidebarRowDrop.Part, of row: SidebarRow, parent: UUID? = nil, in layout: inout SidebarLayout) {
        layout.move(ids[index], to: SidebarRowDrop.pinned(row, in: parent).destination(for: part))
    }

    @Test func `a tab row is split in halves, a folder row in three`() {
        let tab = SidebarRowDrop.favorite(at: 0)
        #expect(tab.part(at: 4, length: 32) == .before)
        #expect(tab.part(at: 15.9, length: 32) == .before)
        #expect(tab.part(at: 16, length: 32) == .after)
        #expect(tab.part(at: 31, length: 32) == .after)
        #expect(tab.part(at: 10, length: 0) == .before)

        let folder = SidebarRowDrop(
            before: .pinned(folder: nil, index: 0),
            after: .pinned(folder: nil, index: 1),
            into: .pinned(folder: ids[0], index: 0),
        )
        #expect(folder.part(at: 9, length: 32) == .before)
        #expect(folder.part(at: 10, length: 32) == .into)
        #expect(folder.part(at: 16, length: 32) == .into)
        #expect(folder.part(at: 22, length: 32) == .into)
        #expect(folder.part(at: 23, length: 32) == .after)
    }

    @Test func `after a row is after all of its tabs`() {
        let split = SplitGroup(tabIDs: [ids[0], ids[1], ids[2]])
        #expect(SidebarRowDrop.today(.split(split, index: 2)) == SidebarRowDrop(before: .today(index: 2), after: .today(index: 5)))
        #expect(SidebarRowDrop.today(.tab(ids[3], index: 5)).after == .today(index: 6))
        #expect(SidebarRowDrop.favorite(at: 1) == SidebarRowDrop(before: .favorites(index: 1), after: .favorites(index: 2)))
        let folder = PinnedFolder(id: ids[4], name: "Travail", isCollapsed: true, items: [.tab(ids[0]), .tab(ids[1])])
        let drop = SidebarRowDrop.pinned(.folder(folder, index: 3), in: ids[5])
        #expect(drop == SidebarRowDrop(
            before: .pinned(folder: ids[5], index: 3),
            after: .pinned(folder: ids[5], index: 4),
            into: .pinned(folder: ids[4], index: 2),
        ))
        #expect(drop.destination(for: .into) == .pinned(folder: ids[4], index: 2))
    }

    @Test func `the top of the first folder puts a tab first among the pinned items`() throws {
        var layout = SidebarLayout()
        let first = layout.addFolder(named: "Travail")
        let second = layout.addFolder(named: "Perso")
        layout.insertToday(ids[0], at: 0)
        try drop(0, on: .before, of: row(first, in: layout), in: &layout)
        #expect(layout.pinned.map(\.id) == [ids[0], first, second])
    }

    @Test func `a tab goes between two collapsed folders from either of them`() throws {
        var layout = SidebarLayout()
        let first = layout.addFolder(named: "Travail")
        let second = layout.addFolder(named: "Perso")
        layout.setFolderCollapsed(first, true)
        layout.insertToday(ids[0], at: 0)
        layout.insertToday(ids[1], at: 0)
        try drop(0, on: .after, of: row(first, in: layout), in: &layout)
        #expect(layout.pinned.map(\.id) == [first, ids[0], second])
        try drop(1, on: .before, of: row(second, in: layout), in: &layout)
        #expect(layout.pinned.map(\.id) == [first, ids[0], ids[1], second])
    }

    @Test func `the bottom of an expanded folder puts a tab first in it`() throws {
        var layout = SidebarLayout()
        let folder = layout.addFolder(named: "Travail")
        layout.insertToday(ids[0], at: 0)
        layout.move(ids[0], to: .pinned(folder: folder, index: 0))
        layout.insertToday(ids[1], at: 0)
        try drop(1, on: .after, of: row(folder, in: layout), in: &layout)
        #expect(try indices(#require(layout.pinned.folder(folder)).items) == [1, 0])
    }

    @Test func `the bottom of the last tab of a folder puts a tab at its end`() throws {
        var layout = SidebarLayout()
        let folder = layout.addFolder(named: "Travail")
        _ = layout.addFolder(named: "Perso")
        for index in 0 ..< 3 {
            layout.insertToday(ids[index], at: 0)
            layout.move(ids[index], to: .pinned(folder: folder, index: index))
        }
        layout.insertToday(ids[3], at: 0)
        try drop(3, on: .after, of: row(ids[2], in: layout, parent: folder), parent: folder, in: &layout)
        #expect(try indices(#require(layout.pinned.folder(folder)).items) == [0, 1, 2, 3])

        // Down one step inside the folder: after the next tab.
        try drop(0, on: .after, of: row(ids[1], in: layout, parent: folder), parent: folder, in: &layout)
        #expect(try indices(#require(layout.pinned.folder(folder)).items) == [1, 0, 2, 3])
    }
}
