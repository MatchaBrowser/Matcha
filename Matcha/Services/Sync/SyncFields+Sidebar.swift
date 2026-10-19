import Foundation

/// Fields of a profile (`SYNC.md` § 2.1).
nonisolated struct SyncProfileFields: Codable, Equatable, Sendable {
    var name: String
    var order: Int
}

/// Fields of a Space: `symbol` as in `SpaceRecord.symbol`, `theme` as in `SpaceTheme` (nil: default theme).
nonisolated struct SyncSpaceFields: Codable, Equatable, Sendable {
    var name: String
    var symbol: String
    var theme: SpaceTheme?
    var order: Int
    var profileId: UUID?
}

/// Fields of a folder of pinned tabs: `icon` as in `FolderRecord.iconValue`, colors as “#RRGGBB”.
nonisolated struct SyncFolderFields: Codable, Equatable, Sendable {
    var name: String
    var order: Int
    var isCollapsed: Bool
    var spaceId: UUID?
    var parentId: UUID?
    var icon: String?
    var textColor: String?
    var backgroundColor: String?
}

/// Placement of a synced tab; any other value makes the record ignored.
nonisolated enum SyncTabPlace: String, Codable, Sendable {
    case favorite
    case pinned
    case today
}

/// Fields of a tab (`SYNC.md` § 2.1 and § 2.4): original address and title of a favorite or a pinned tab, current
/// address and title of a today tab; `profileId` for a favorite, `spaceId` for the others.
nonisolated struct SyncTabFields: Codable, Equatable, Sendable {
    var place: SyncTabPlace
    var url: URL?
    var title: String?
    var order: Int
    var profileId: UUID?
    var spaceId: UUID?
    var folderId: UUID?
    /// Last use of a today tab; nil for the others.
    var lastActivity: Date?

    /// True if `other` only differs by the address, the title or the last use of a today tab: a change that waits
    /// for the page to be stable before being sent (`SYNC.md` § 2.4).
    func differsOnlyByPage(from other: SyncTabFields) -> Bool {
        guard place == .today, other.place == .today else {
            return false
        }
        var mine = self
        mine.url = other.url
        mine.title = other.title
        mine.lastActivity = other.lastActivity
        return mine == other
    }
}
