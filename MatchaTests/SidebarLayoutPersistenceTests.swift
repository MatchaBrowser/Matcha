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

    /// Favoris 0 et 1 ; épinglés : 2, dossier Travail (3, sous-dossier Client replié (4)), 5 ; du jour : 6, 7.
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
