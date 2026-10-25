import Foundation
@testable import Matcha
import Testing

struct SidebarLayoutPersistenceTests {
    private let ids = (0 ..< 8).map { _ in UUID() }

    private struct RichLayout {
        var layout: SidebarLayout
        let work: UUID
        let client: UUID
    }

    /// Favorites 0 and 1; pinned: 2, folder Travail (3, collapsed subfolder Client (4)), 5; today: 6, 7.
    private func richLayout() -> RichLayout {
        var layout = SidebarLayout()
        for id in ids {
            layout.insertToday(id, at: layout.today.count)
        }
        layout.move(ids[0], to: .favorites(index: 0))
        layout.move(ids[1], to: .favorites(index: 1))
        layout.move(ids[2], to: .pinned(folder: nil, index: 0))
        let work = layout.addFolder(named: "Travail")
        layout.move(ids[3], to: .pinned(folder: work, index: 0))
        let client = layout.addFolder(named: "Client", in: work)
        layout.setFolderCollapsed(client, true)
        layout.move(ids[4], to: .pinned(folder: client, index: 0))
        layout.move(ids[5], to: .pinned(folder: nil, index: 99))
        return RichLayout(layout: layout, work: work, client: client)
    }

    @Test func `positions describe every tab`() {
        let rich = richLayout()
        let (layout, work, client) = (rich.layout, rich.work, rich.client)
        let positions = layout.positions
        #expect(positions.count == 8)
        #expect(positions[ids[1]] == SidebarPosition(place: .favorite, order: 1))
        #expect(positions[ids[2]] == SidebarPosition(place: .pinned, order: 0))
        #expect(positions[ids[3]] == SidebarPosition(place: .pinned, order: 0, folderID: work))
        #expect(positions[ids[4]] == SidebarPosition(place: .pinned, order: 0, folderID: client))
        #expect(positions[ids[5]] == SidebarPosition(place: .pinned, order: 2))
        #expect(positions[ids[7]] == SidebarPosition(place: .today, order: 1))
        #expect(layout.folderEntries == [
            FolderEntry(id: work, name: "Travail", isCollapsed: false, parentID: nil, order: 1),
            FolderEntry(id: client, name: "Client", isCollapsed: true, parentID: work, order: 1),
        ])
    }

    @Test func `round trip gives back the same layout`() {
        let layout = richLayout().layout
        let rebuilt = SidebarLayout(positions: layout.positions, folders: layout.folderEntries)
        #expect(rebuilt == layout)
    }

    /// Icon and colors of each folder, subfolders included, go through the stored entries.
    @Test func `folder appearances survive the round trip`() {
        var rich = richLayout()
        let work = FolderAppearance(icon: .symbol("briefcase"), textColor: ThemeColor(rgb: 0x007AFF))
        let client = FolderAppearance(icon: .emoji("🌿"), backgroundColor: ThemeColor(rgb: 0x34C759))
        rich.layout.setFolderAppearance(rich.work, work)
        rich.layout.setFolderAppearance(rich.client, client)
        #expect(rich.layout.folderEntries.map(\.appearance) == [work, client])

        let rebuilt = SidebarLayout(positions: rich.layout.positions, folders: rich.layout.folderEntries)
        #expect(rebuilt == rich.layout)
        #expect(rebuilt.pinned.folder(rich.client)?.appearance == client)
        #expect(rebuilt.pinned.folder(rich.client)?.isCollapsed == true)
    }

    @Test func `orders need not be contiguous`() {
        let positions = [
            ids[0]: SidebarPosition(place: .today, order: 30),
            ids[1]: SidebarPosition(place: .today, order: 10),
            ids[2]: SidebarPosition(place: .today, order: 20),
        ]
        #expect(SidebarLayout(positions: positions, folders: []).today == [ids[1], ids[2], ids[0]])
    }

    @Test func `unknown folders send their contents to the root`() {
        let missing = UUID()
        let folder = FolderEntry(id: UUID(), name: "Perdu", isCollapsed: false, parentID: missing, order: 1)
        let positions = [
            ids[0]: SidebarPosition(place: .pinned, order: 0, folderID: missing),
            ids[1]: SidebarPosition(place: .pinned, order: 0, folderID: folder.id),
        ]
        let layout = SidebarLayout(positions: positions, folders: [folder])
        #expect(layout.pinned.map(\.id) == [ids[0], folder.id])
        #expect(layout.pinned.folder(folder.id)?.items == [.tab(ids[1])])
    }

    @Test func `two folders with the same identifier keep the first one`() {
        let id = UUID()
        let first = FolderEntry(id: id, name: "First", isCollapsed: false, parentID: nil, order: 0)
        let second = FolderEntry(id: id, name: "Second", isCollapsed: true, parentID: nil, order: 1)
        let positions = [ids[0]: SidebarPosition(place: .pinned, order: 0, folderID: id)]
        let layout = SidebarLayout(positions: positions, folders: [first, second])
        #expect(layout.pinned.map(\.id) == [id])
        #expect(layout.folderEntries.map(\.name) == ["First"])
        #expect(layout.pinned.folder(id)?.items == [.tab(ids[0])])
    }

    @Test func `positions carry split membership and fractions`() throws {
        var layout = richLayout().layout
        let joined = layout.joinSplit(ids[7], anchor: ids[6], at: 1)
        let groupID = try #require(joined)
        layout.setSplitFractions(groupID, [0.3, 0.7])
        let positions = layout.positions
        #expect(positions[ids[6]] == SidebarPosition(place: .today, order: 0, splitGroupID: groupID, splitFraction: 0.3))
        #expect(positions[ids[7]] == SidebarPosition(place: .today, order: 1, splitGroupID: groupID, splitFraction: 0.7))
        #expect(positions[ids[2]]?.splitGroupID == nil)
        #expect(positions[ids[0]]?.splitFraction == 0)
    }

    @Test func `split groups survive the round trip`() throws {
        var rich = richLayout()
        let todayGroup = rich.layout.joinSplit(ids[7], anchor: ids[6], at: 0)
        // A pinned tab from the root that joins the one in the Travail folder.
        let joined = rich.layout.joinSplit(ids[5], anchor: ids[3], at: 1)
        try #require(todayGroup != nil)
        let pinnedGroup = try #require(joined)
        rich.layout.setSplitFractions(pinnedGroup, [0.25, 0.75])
        expectSplitInvariants(rich.layout)
        #expect(rich.layout.pinned.folder(rich.work)?.items.prefix(2) == [.tab(ids[3]), .tab(ids[5])])

        let rebuilt = SidebarLayout(positions: rich.layout.positions, folders: rich.layout.folderEntries)
        #expect(rebuilt == rich.layout)
        #expect(rebuilt.splits.count == 2)
    }

    @Test func `invalid saved groups are repaired or dropped`() {
        let single = UUID()
        let mixed = UUID()
        let crowded = UUID()
        let scattered = UUID()
        let folder = FolderEntry(id: UUID(), name: "Travail", isCollapsed: false, parentID: nil, order: 0)
        var positions: [UUID: SidebarPosition] = [:]
        // Group of a single tab: dropped.
        positions[ids[0]] = SidebarPosition(place: .today, order: 0, splitGroupID: single, splitFraction: 1)
        // A favorite and two containers: only the members in the first one's container remain (the folder),
        // and share 0 gives equal shares.
        positions[ids[1]] = SidebarPosition(place: .favorite, order: 0, splitGroupID: mixed, splitFraction: 0.5)
        positions[ids[2]] = SidebarPosition(place: .pinned, order: 0, folderID: folder.id, splitGroupID: mixed, splitFraction: 0)
        positions[ids[3]] = SidebarPosition(place: .pinned, order: 1, folderID: folder.id, splitGroupID: mixed, splitFraction: 0.5)
        positions[ids[4]] = SidebarPosition(place: .today, order: 1, splitGroupID: mixed, splitFraction: 0.5)
        let rebuilt = SidebarLayout(positions: positions, folders: [folder])
        expectSplitInvariants(rebuilt)
        #expect(rebuilt.splits.map(\.id) == [mixed])
        #expect(rebuilt.split(withID: mixed)?.tabIDs == [ids[2], ids[3]])
        #expect(rebuilt.split(withID: mixed)?.fractions == [0.5, 0.5])

        // Five members, not adjacent: the first four, grouped after the first.
        var crowd: [UUID: SidebarPosition] = [:]
        for (order, id) in ids.enumerated() {
            let member = order.isMultiple(of: 2) || order == 7
            crowd[id] = SidebarPosition(place: .today, order: order, splitGroupID: member ? crowded : scattered, splitFraction: 0.2)
        }
        let repaired = SidebarLayout(positions: crowd, folders: [])
        expectSplitInvariants(repaired)
        #expect(repaired.split(withID: crowded)?.tabIDs == [ids[0], ids[2], ids[4], ids[6]])
        #expect(repaired.today.prefix(4) == [ids[0], ids[2], ids[4], ids[6]])
        let fractions = repaired.split(withID: crowded)?.fractions ?? []
        #expect(fractions.count == 4)
        #expect(fractions.allSatisfy { abs($0 - 0.25) < 1e-12 })
    }

    @Test func `folders caught in a loop are not lost`() {
        let first = UUID()
        let second = UUID()
        let folders = [
            FolderEntry(id: first, name: "A", isCollapsed: false, parentID: second, order: 0),
            FolderEntry(id: second, name: "B", isCollapsed: false, parentID: first, order: 1),
        ]
        let positions = [ids[0]: SidebarPosition(place: .pinned, order: 0, folderID: second)]
        let layout = SidebarLayout(positions: positions, folders: folders)
        #expect(layout.pinned.folder(first) != nil)
        #expect(layout.pinned.folder(second) != nil)
        #expect(layout.orderedTabIDs == [ids[0]])
    }
}
