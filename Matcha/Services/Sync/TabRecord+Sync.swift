import Foundation

/// A tab with its synced fields, both ways side by side (audit C6). Favorite and pinned tab: their original address
/// and title travel, only web addresses, without user name nor password. A today tab stays on this Mac (`SYNC.md`
/// § 2.4).
extension TabRecord {
    /// Nil for a today tab, a tab without a place, or without its profile (favorite) or its Space (pinned tab): it
    /// isn't sent.
    var syncFields: SyncTabFields? {
        switch place {
        case .favorite:
            guard let profileID = profile?.id else {
                return nil
            }
            return SyncTabFields(
                place: .favorite,
                url: SyncWebURL.shared(originURL),
                title: pinnedTitle ?? title,
                order: Double(order),
                profileId: profileID,
            )
        case .pinned:
            guard let spaceID = space?.id else {
                return nil
            }
            return SyncTabFields(
                place: .pinned,
                url: SyncWebURL.shared(originURL),
                title: pinnedTitle ?? title,
                order: Double(order),
                spaceId: spaceID,
                folderId: folder?.id,
            )
        case .today, nil:
            return nil
        }
    }

    /// Original address of a favorite or a pinned tab.
    private var originURL: URL? {
        pinnedURL ?? url
    }

    /// Favorite or pinned tab whose original address isn't a web address (local file…): it stays on this Mac, neither
    /// sent nor deleted elsewhere (`SYNC.md` § 5).
    var isLocalOnly: Bool {
        guard place == .favorite || place == .pinned, let originURL else {
            return false
        }
        return !SyncWebURL.isWeb(originURL)
    }

    /// Their original address changes; their current address follows it if they had not left the old one; a local one
    /// keeps its address and title. A today tab here that becomes a favorite or a pinned tab elsewhere takes its new
    /// place and address. `isNew`: just created, it won't select itself. Never called for a received today tab
    /// (`SyncRecordWriter`).
    func apply(
        _ fields: SyncTabFields,
        isNew: Bool,
        folder newFolder: FolderRecord?,
        profile newProfile: ProfileRecord?,
        space newSpace: SpaceRecord?,
    ) {
        let newPlace = fields.place.tabPlace
        if !isLocalOnly || place == .today {
            let followsOrigin = isNew || place == .today || url == pinnedURL
            pinnedURL = fields.url
            pinnedTitle = fields.title
            if followsOrigin {
                url = fields.url
                title = fields.title
            }
            if isNew {
                lastActivity = .distantPast
            }
        }
        if place != newPlace {
            splitGroupID = nil
            splitFraction = 0
        }
        place = newPlace
        order = SyncOrder.integer(fields.order)
        folder = newFolder
        profile = newProfile
        space = newSpace
    }
}

nonisolated extension SyncTabPlace {
    var tabPlace: TabPlace {
        switch self {
        case .favorite: .favorite
        case .pinned: .pinned
        case .today: .today
        }
    }
}
