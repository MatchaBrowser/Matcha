import Foundation

/// A tab with its synced fields, both ways side by side (audit C6). Favorite and pinned tab: their original address
/// and title travel; today tab: its address, title and last use (`SYNC.md` § 2.4). Only web addresses travel, without
/// user name nor password.
extension TabRecord {
    /// Nil for a tab without a place, or without its profile (favorite) or its Space (the others): it isn't sent.
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
        case .today:
            guard let spaceID = space?.id else {
                return nil
            }
            let isWeb = !showsNonWebPage
            return SyncTabFields(
                place: .today,
                url: isWeb ? SyncWebURL.shared(url) : nil,
                title: isWeb ? title : nil,
                order: Double(order),
                spaceId: spaceID,
                lastActivity: lastActivity,
            )
        case nil:
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

    /// Shows a page that isn't a web address (local file, `about:`…): its address doesn't travel.
    var showsNonWebPage: Bool {
        url.map { !SyncWebURL.isWeb($0) } ?? false
    }

    /// Favorite and pinned tab: their original address changes; their current address follows it if they had not left
    /// the old one; a local one keeps its address and title. Today tab: its current address. `isNew`: just created, it
    /// won't select itself.
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
        } else if !isLocalOnly || place == .today {
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
