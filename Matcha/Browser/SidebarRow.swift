import Foundation

/// Row of the sidebar: a tab, a split (a single row for all its tabs) or a folder.
/// `index`: position of the tab, of the first member or of the folder in its container (drop “before the row”).
nonisolated enum SidebarRow: Equatable, Sendable, Identifiable {
    case tab(UUID, index: Int)
    case split(SplitGroup, index: Int)
    case folder(PinnedFolder, index: Int)

    /// Tab, group or folder.
    var id: UUID {
        switch self {
        case let .tab(id, _): id
        case let .split(group, _): group.id
        case let .folder(folder, _): folder.id
        }
    }

    var index: Int {
        switch self {
        case let .tab(_, index), let .split(_, index), let .folder(_, index): index
        }
    }
}

/// Rows displayed by the sidebar: a split member gives the row of its split if it is the first member,
/// and nothing otherwise.
nonisolated extension SidebarLayout {
    var todayRows: [SidebarRow] {
        today.enumerated().compactMap { index, id in row(forTab: id, index: index) }
    }

    /// Rows of one level of the pinned tabs (`items`: the root or the content of a folder).
    func pinnedRows(_ items: [PinnedItem]) -> [SidebarRow] {
        items.enumerated().compactMap { index, item in
            switch item {
            case let .tab(id): row(forTab: id, index: index)
            case let .folder(folder): .folder(folder, index: index)
            }
        }
    }

    private func row(forTab id: UUID, index: Int) -> SidebarRow? {
        guard let group = split(containing: id) else {
            return .tab(id, index: index)
        }
        return group.tabIDs.first == id ? .split(group, index: index) : nil
    }
}
