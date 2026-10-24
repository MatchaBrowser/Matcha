import Foundation

/// Where an item dropped on a sidebar row or a favorite tile goes, according to the part under the pointer: before
/// the row, after it, or into it (a folder). The row shows that part during the drag. Pure type.
nonisolated struct SidebarRowDrop: Equatable, Sendable {
    enum Part: Equatable, Sendable {
        case before
        case into
        case after
    }

    /// Share of a folder's row, at each end, that places the item before or after it rather than into it.
    static let folderEdgeShare = 0.3

    let before: SidebarDestination
    let after: SidebarDestination
    /// Content of a folder (at its end); nil for a tab, a split or a favorite, which only take items before or after.
    var into: SidebarDestination?

    /// A today row.
    static func today(_ row: SidebarRow) -> SidebarRowDrop {
        SidebarRowDrop(before: .today(index: row.index), after: .today(index: row.nextIndex))
    }

    /// A row of the pinned items of `parent` (nil: the root). The bottom of an expanded folder places the item first
    /// in it, right above its content; that of a collapsed folder, after it.
    static func pinned(_ row: SidebarRow, in parent: UUID?) -> SidebarRowDrop {
        let before = SidebarDestination.pinned(folder: parent, index: row.index)
        guard case let .folder(folder, _) = row else {
            return SidebarRowDrop(before: before, after: .pinned(folder: parent, index: row.nextIndex))
        }
        return SidebarRowDrop(
            before: before,
            after: folder.isCollapsed ? .pinned(folder: parent, index: row.nextIndex) : .pinned(folder: folder.id, index: 0),
            into: .pinned(folder: folder.id, index: folder.items.count),
        )
    }

    /// The favorite tile at `index`.
    static func favorite(at index: Int) -> SidebarRowDrop {
        SidebarRowDrop(before: .favorites(index: index), after: .favorites(index: index + 1))
    }

    /// Part under the pointer, `position` points from the start of the row (top of a row, leading edge of a tile)
    /// whose length is `length`: halves, or for a folder, its content between two edges of `folderEdgeShare`.
    func part(at position: Double, length: Double) -> Part {
        guard length > 0 else {
            return .before
        }
        let fraction = position / length
        guard into != nil else {
            return fraction < 0.5 ? .before : .after
        }
        if fraction < Self.folderEdgeShare {
            return .before
        }
        return fraction > 1 - Self.folderEdgeShare ? .after : .into
    }

    func destination(for part: Part) -> SidebarDestination {
        switch part {
        case .before: before
        case .after: after
        case .into: into ?? after
        }
    }
}
