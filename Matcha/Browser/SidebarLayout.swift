import Foundation

/// Place of a tab in the sidebar.
nonisolated enum TabPlace: String, CaseIterable, Sendable {
    case favorite
    case pinned
    case today
}

/// Where to drop a tab: a section (or a folder of pinned tabs) and a rank in it.
/// The rank is read before the move: dropping “before item no. i” gives `index: i`.
nonisolated enum SidebarDestination: Equatable, Sendable {
    case favorites(index: Int)
    /// Pinned tabs: at the root (`folder` nil) or in a folder.
    case pinned(folder: UUID?, index: Int)
    case today(index: Int)

    var index: Int {
        switch self {
        case let .favorites(index), let .pinned(_, index), let .today(index): index
        }
    }
}

/// Arrangement of the tabs in the sidebar: favorites, pinned tabs (with folders), today tabs.
/// Pure type: it only knows the tabs' identifiers.
nonisolated struct SidebarLayout: Equatable, Sendable {
    private(set) var favorites: [UUID] = []
    private(set) var pinned: [PinnedItem] = []
    private(set) var today: [UUID] = []
    /// The Space's splits: 2 to 4 neighboring tabs of the same container (see SidebarLayout+Splits), sorted by
    /// identifier. Changed only by `setSplits`; `normalizeSplits` restores their rules after each change.
    private(set) var splits: [SplitGroup] = []

    /// All tabs in sidebar order: favorites, pinned tabs (folders included), then today tabs.
    var orderedTabIDs: [UUID] {
        favorites + pinned.flatMap(\.tabIDs) + today
    }

    func place(of id: UUID) -> TabPlace? {
        if favorites.contains(id) {
            return .favorite
        }
        if today.contains(id) {
            return .today
        }
        if pinned.contains(where: { $0.tabIDs.contains(id) }) {
            return .pinned
        }
        return nil
    }

    /// Places the tab among the today tabs, at `index` (clamped), removing it from elsewhere (and from its split).
    mutating func insertToday(_ id: UUID, at index: Int) {
        detachFromSplit(id)
        takeOut(id)
        today.insert(id, at: Self.clamp(index, count: today.count))
        normalizeSplits()
    }

    /// Changes the tab's place: at the end of the favorites or pinned tabs, or at the top of the today tabs.
    /// No effect if it is already there.
    mutating func setPlace(_ id: UUID, to place: TabPlace) {
        guard self.place(of: id) != place else {
            return
        }
        detachFromSplit(id)
        takeOut(id)
        switch place {
        case .favorite: favorites.append(id)
        case .pinned: pinned.append(.tab(id))
        case .today: today.insert(id, at: 0)
        }
        normalizeSplits()
    }

    /// Moves an already placed tab to `destination` (drag and drop); it leaves its split. An unknown folder
    /// sends the tab to the end of the pinned tabs.
    mutating func move(_ id: UUID, to destination: SidebarDestination) {
        guard place(of: id) != nil else {
            return
        }
        detachFromSplit(id)
        placeTab(id, at: destination)
        normalizeSplits()
    }

    /// Primitive without split rules: moves the placed tab `id` to `destination` (rank read before the move).
    mutating func placeTab(_ id: UUID, at destination: SidebarDestination) {
        var index = destination.index
        // In the same container, removing the tab shifts the ranks that follow it by one.
        if let source = container(of: id), source.container == Container(destination), source.index < index {
            index -= 1
        }
        takeOut(id)
        switch destination {
        case .favorites:
            favorites.insert(id, at: Self.clamp(index, count: favorites.count))
        case .today:
            today.insert(id, at: Self.clamp(index, count: today.count))
        case let .pinned(folder, _):
            if !pinned.insert(.tab(id), inFolder: folder, at: index) {
                pinned.append(.tab(id))
            }
        }
    }

    /// Primitive: places `id` right after `previous`, in the container of `previous`; no effect if already there.
    mutating func placeTab(_ id: UUID, after previous: UUID) {
        guard id != previous, let anchor = container(of: previous) else {
            return
        }
        if let current = container(of: id), current.container == anchor.container, current.index == anchor.index + 1 {
            return
        }
        placeTab(id, at: anchor.container.destination(at: anchor.index + 1))
    }

    /// Replaces the splits, then restores their rules.
    mutating func setSplits(_ groups: [SplitGroup]) {
        splits = groups
        normalizeSplits()
    }

    /// Creates an empty folder of pinned tabs in `parent` (nil: the root), at `index` or at the end.
    @discardableResult
    mutating func addFolder(id: UUID = UUID(), named name: String, in parent: UUID? = nil, at index: Int? = nil) -> UUID {
        let folder = PinnedFolder(id: id, name: name)
        if !pinned.insert(.folder(folder), inFolder: parent, at: index ?? Int.max) {
            pinned.append(.folder(folder))
        }
        normalizeSplits()
        return folder.id
    }

    mutating func renameFolder(_ id: UUID, to name: String) {
        pinned.updateFolder(id) { $0.name = name }
    }

    mutating func setFolderCollapsed(_ id: UUID, _ isCollapsed: Bool) {
        pinned.updateFolder(id) { $0.isCollapsed = isCollapsed }
    }

    mutating func setFolderAppearance(_ id: UUID, _ appearance: FolderAppearance) {
        pinned.updateFolder(id) { $0.appearance = appearance }
    }

    /// Moves a folder among the pinned tabs. Refused outside the pinned tabs, or into itself or one of
    /// its subfolders.
    mutating func moveFolder(_ id: UUID, to destination: SidebarDestination) {
        guard case let .pinned(target, requestedIndex) = destination,
              let source = pinned.location(of: id),
              let folder = pinned.folder(id),
              target != id,
              target.map({ folder.items.folder($0) == nil }) ?? true
        else {
            return
        }
        var index = requestedIndex
        if source.parent == target, source.index < index {
            index -= 1
        }
        guard let item = pinned.removeItem(id) else {
            return
        }
        if !pinned.insert(item, inFolder: target, at: index) {
            pinned.append(item)
        }
        normalizeSplits()
    }

    /// Deletes a folder; its content takes its place in the parent folder.
    mutating func removeFolder(_ id: UUID) {
        guard let location = pinned.location(of: id), case let .folder(folder) = pinned.removeItem(id) else {
            return
        }
        for (offset, child) in folder.items.enumerated() {
            pinned.insert(child, inFolder: location.parent, at: location.index + offset)
        }
        normalizeSplits()
    }

    /// Replaces the favorites with `ids`, in this order (each one is removed from elsewhere).
    mutating func setFavorites(_ ids: [UUID]) {
        favorites = []
        for id in ids {
            takeOut(id)
            favorites.append(id)
        }
        normalizeSplits()
    }

    /// Removes the tab, wherever it is (and from its split).
    mutating func remove(_ id: UUID) {
        takeOut(id)
        normalizeSplits()
    }

    /// List that directly contains a tab.
    enum Container: Equatable {
        case favorites
        case pinned(folder: UUID?)
        case today

        init(_ destination: SidebarDestination) {
            switch destination {
            case .favorites: self = .favorites
            case let .pinned(folder, _): self = .pinned(folder: folder)
            case .today: self = .today
            }
        }

        /// Destination “at rank `index`” of this list.
        func destination(at index: Int) -> SidebarDestination {
            switch self {
            case .favorites: .favorites(index: index)
            case let .pinned(folder): .pinned(folder: folder, index: index)
            case .today: .today(index: index)
            }
        }
    }

    /// List that directly contains the tab, and its rank in it.
    func container(of id: UUID) -> (container: Container, index: Int)? {
        if let index = favorites.firstIndex(of: id) {
            return (.favorites, index)
        }
        if let index = today.firstIndex(of: id) {
            return (.today, index)
        }
        return pinned.location(of: id).map { (.pinned(folder: $0.parent), $0.index) }
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        min(max(index, 0), count)
    }

    /// Former body of `remove`: removes the tab from the favorites, the today tabs and the pinned tabs.
    private mutating func takeOut(_ id: UUID) {
        favorites.removeAll { $0 == id }
        today.removeAll { $0 == id }
        pinned = pinned.removingTab(id)
    }

    /// Removes the tab from the split that contains it (the split is undone by `normalizeSplits` below two tabs).
    private mutating func detachFromSplit(_ id: UUID) {
        if let index = splits.firstIndex(where: { $0.contains(id) }) {
            splits[index].remove(id)
        }
    }

    /// Restores the split rules: members placed outside the favorites, in a single container (the first member's),
    /// 4 at most, gathered in sidebar order; a tab in only one split; 2 members at least. One pass is enough: a
    /// gathered group contains only its members, the following ones do not get into it.
    private mutating func normalizeSplits() {
        guard !splits.isEmpty else {
            return
        }
        let rank = Dictionary(orderedTabIDs.enumerated().map { ($1, $0) }) { first, _ in first }
        var claimed: Set<UUID> = []
        var kept: [SplitGroup] = []
        for var group in splits {
            let present = group.tabIDs
                .filter { rank[$0] != nil && place(of: $0) != .favorite && !claimed.contains($0) }
                .sorted { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
            guard let first = present.first, let home = container(of: first)?.container else {
                continue
            }
            let members = Array(present.filter { container(of: $0)?.container == home }.prefix(SplitGroup.paneCount.upperBound))
            guard members.count >= SplitGroup.paneCount.lowerBound else {
                continue
            }
            for (previous, id) in zip(members, members.dropFirst()) {
                placeTab(id, after: previous)
            }
            group.setMembers(members)
            claimed.formUnion(members)
            kept.append(group)
        }
        kept.sort { $0.id.uuidString < $1.id.uuidString }
        if kept != splits {
            splits = kept
        }
    }
}
