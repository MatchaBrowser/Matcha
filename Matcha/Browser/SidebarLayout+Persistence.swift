import Foundation

/// Position of a tab in the sidebar, as saved.
nonisolated struct SidebarPosition: Equatable, Sendable {
    var place: TabPlace
    /// Rank in its container: favorites, root of the pinned tabs or folder, today tabs.
    var order: Int
    /// Folder that contains the pinned tab, nil at the root.
    var folderID: UUID?
    /// The tab's split and the width share of its pane.
    var splitGroupID: UUID?
    var splitFraction = 0.0
}

/// Folder of pinned tabs, as saved.
nonisolated struct FolderEntry: Equatable, Sendable {
    var id: UUID
    var name: String
    var isCollapsed: Bool
    /// Parent folder, nil at the root of the pinned tabs.
    var parentID: UUID?
    /// Rank in its container, on the same scale as the tabs.
    var order: Int
    var appearance = FolderAppearance()
}

/// Conversion of the in-memory layout to its saved form (flat positions), and back.
nonisolated extension SidebarLayout {
    /// Position of each placed tab, with its split.
    var positions: [UUID: SidebarPosition] {
        var result: [UUID: SidebarPosition] = [:]
        for (order, id) in favorites.enumerated() {
            result[id] = SidebarPosition(place: .favorite, order: order)
        }
        for (order, id) in today.enumerated() {
            result[id] = SidebarPosition(place: .today, order: order)
        }
        Self.collectPinned(pinned, in: nil, positions: &result)
        for group in splits {
            for (offset, id) in group.tabIDs.enumerated() {
                result[id]?.splitGroupID = group.id
                result[id]?.splitFraction = group.fractions[offset]
            }
        }
        return result
    }

    /// Folders of pinned tabs, with their parent and rank.
    var folderEntries: [FolderEntry] {
        var result: [FolderEntry] = []
        Self.collectFolders(pinned, in: nil, entries: &result)
        return result
    }

    /// Rebuilds the layout: each container in increasing order of rank. A folder whose parent is unknown, or
    /// caught in a loop, goes to the root; so does a pinned tab in an unknown folder.
    /// The saved splits are repaired if needed (see `restoreSplits`).
    init(positions: [UUID: SidebarPosition], folders: [FolderEntry]) {
        self.init()
        for (id, _) in positions.filter({ $0.value.place == .favorite }).sorted(by: Self.byOrder) {
            setPlace(id, to: .favorite)
        }
        for (id, _) in positions.filter({ $0.value.place == .today }).sorted(by: Self.byOrder) {
            insertToday(id, at: today.count)
        }
        let knownFolders = Set(folders.map(\.id))
        var pinnedTabs = positions.filter { $0.value.place == .pinned }
        for (id, position) in pinnedTabs where position.folderID.map({ !knownFolders.contains($0) }) ?? false {
            pinnedTabs[id]?.folderID = nil
        }
        // Nothing in the store prevents two folders with the same identifier (no uniqueness with CloudKit): the first
        // one is kept, as `SpaceStore` does (review ON9).
        var remaining = Dictionary(folders.map { ($0.id, $0) }) { first, _ in first }
        for (id, entry) in remaining where entry.parentID.map({ !knownFolders.contains($0) }) ?? false {
            remaining[id]?.parentID = nil
        }
        fillPinned(in: nil, tabs: pinnedTabs, folders: &remaining)
        // Folders caught in a parent loop: never reached from the root. The pinned tabs of the root are
        // already placed; only those of folders remain to be placed.
        let tabsInFolders = pinnedTabs.filter { $0.value.folderID != nil }
        while let orphan = remaining.values.min(by: { $0.order < $1.order }) {
            remaining[orphan.id]?.parentID = nil
            fillPinned(in: nil, tabs: tabsInFolders, folders: &remaining)
        }
        restoreSplits(from: positions)
    }

    /// Groups the placed tabs by split, in sidebar order. Normalization repairs an invalid store (sync, older
    /// version): a single-tab group is dropped, a favorite removed, members outside the first member's container
    /// removed, 4 members at most, members gathered after the first one, invalid shares replaced by equal
    /// shares.
    private mutating func restoreSplits(from positions: [UUID: SidebarPosition]) {
        let rank = Dictionary(orderedTabIDs.enumerated().map { ($1, $0) }) { first, _ in first }
        var members: [UUID: [(id: UUID, fraction: Double)]] = [:]
        for (id, position) in positions where rank[id] != nil {
            if let groupID = position.splitGroupID {
                members[groupID, default: []].append((id, position.splitFraction))
            }
        }
        let candidates = members.map { groupID, entries in
            let sorted = entries.sorted { (rank[$0.id] ?? 0) < (rank[$1.id] ?? 0) }
            return SplitGroup(id: groupID, tabIDs: sorted.map(\.id), fractions: sorted.map(\.fraction))
        }
        // Fixed order: an invalid store is always repaired the same way.
        setSplits(candidates.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    /// Adds, in order of rank, the tabs and folders of `parent`, then the content of each folder.
    /// Each placed folder is removed from `folders`.
    private mutating func fillPinned(in parent: UUID?, tabs: [UUID: SidebarPosition], folders: inout [UUID: FolderEntry]) {
        enum Item { case tab(UUID), folder(FolderEntry) }
        func key(of item: Item) -> String {
            switch item {
            case let .tab(id): id.uuidString
            case let .folder(entry): entry.id.uuidString
            }
        }
        let children = tabs.filter { $0.value.folderID == parent }.map { (order: $0.value.order, item: Item.tab($0.key)) }
            + folders.values.filter { $0.parentID == parent }.map { (order: $0.order, item: Item.folder($0)) }
        // Equal ranks (two synced Macs): the identifier breaks the tie.
        for child in children.sorted(by: { ($0.order, key(of: $0.item)) < ($1.order, key(of: $1.item)) }) {
            switch child.item {
            case let .tab(id):
                setPlace(id, to: .pinned)
                move(id, to: .pinned(folder: parent, index: Int.max))
            case let .folder(entry):
                folders[entry.id] = nil
                addFolder(id: entry.id, named: entry.name, in: parent)
                setFolderCollapsed(entry.id, entry.isCollapsed)
                setFolderAppearance(entry.id, entry.appearance)
                fillPinned(in: entry.id, tabs: tabs, folders: &folders)
            }
        }
    }

    private static func collectPinned(_ items: [PinnedItem], in folder: UUID?, positions: inout [UUID: SidebarPosition]) {
        for (order, item) in items.enumerated() {
            switch item {
            case let .tab(id):
                positions[id] = SidebarPosition(place: .pinned, order: order, folderID: folder)
            case let .folder(child):
                collectPinned(child.items, in: child.id, positions: &positions)
            }
        }
    }

    private static func collectFolders(_ items: [PinnedItem], in parent: UUID?, entries: inout [FolderEntry]) {
        for (order, item) in items.enumerated() {
            guard case let .folder(folder) = item else {
                continue
            }
            entries.append(FolderEntry(
                id: folder.id,
                name: folder.name,
                isCollapsed: folder.isCollapsed,
                parentID: parent,
                order: order,
                appearance: folder.appearance,
            ))
            collectFolders(folder.items, in: folder.id, entries: &entries)
        }
    }

    /// By rank, then by identifier (equal ranks coming from two synced Macs).
    private static func byOrder(_ lhs: (key: UUID, value: SidebarPosition), _ rhs: (key: UUID, value: SidebarPosition)) -> Bool {
        (lhs.value.order, lhs.key.uuidString) < (rhs.value.order, rhs.key.uuidString)
    }
}
