import Foundation

/// A tab with its synced fields, both ways side by side (audit C6). Favorite and pinned tab: their original address
/// and title travel; today tab: its address, title and last use (`SYNC.md` § 2.4).
extension TabRecord {
    /// Nil for a tab without a place, or without its profile (favorite) or its Space (the others): it isn't sent.
    var syncFields: SyncTabFields? {
        switch place {
        case .favorite:
            guard let profileID = profile?.id else {
                return nil
            }
            return SyncTabFields(place: .favorite, url: pinnedURL ?? url, title: pinnedTitle ?? title, order: order, profileId: profileID)
        case .pinned:
            guard let spaceID = space?.id else {
                return nil
            }
            return SyncTabFields(
                place: .pinned,
                url: pinnedURL ?? url,
                title: pinnedTitle ?? title,
                order: order,
                spaceId: spaceID,
                folderId: folder?.id,
            )
        case .today:
            guard let spaceID = space?.id else {
                return nil
            }
            return SyncTabFields(place: .today, url: url, title: title, order: order, spaceId: spaceID, lastActivity: lastActivity)
        case nil:
            return nil
        }
    }

    /// Favorite and pinned tab: their original address changes; their current address follows it if they had not left
    /// the old one. Today tab: its current address. `isNew`: just created, it won't select itself.
    func apply(
        _ fields: SyncTabFields,
        isNew: Bool,
        folder newFolder: FolderRecord?,
        profile newProfile: ProfileRecord?,
        space newSpace: SpaceRecord?,
    ) {
        let newPlace = fields.place.tabPlace
        if newPlace == .today {
            pinnedURL = nil
            pinnedTitle = nil
            url = fields.url
            title = fields.title
            lastActivity = fields.lastActivity ?? lastActivity
        } else {
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
        order = fields.order
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
