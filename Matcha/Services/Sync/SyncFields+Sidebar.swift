import Foundation

// Fields of the sidebar's records (`SYNC.md` § 2.1), read leniently (§ 2.9): an unreadable field takes its default
// value, except the parent, without which the record is ignored.

/// Fields of a profile.
nonisolated struct SyncProfileFields: Codable, Equatable, Sendable {
    var name: String
    var order: Double

    init(name: String, order: Double) {
        self.name = name
        self.order = order
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenient(String.self, forKey: .name) ?? ""
        order = container.order(forKey: .order)
    }
}

/// Fields of a Space: `symbol` as in `SpaceRecord.symbol`, `theme` as in `SpaceTheme` (nil: default theme).
nonisolated struct SyncSpaceFields: Codable, Equatable, Sendable {
    var name: String
    var symbol: String
    var theme: SpaceTheme?
    var order: Double
    var profileId: UUID

    init(name: String, symbol: String, theme: SpaceTheme?, order: Double, profileId: UUID) {
        self.name = name
        self.symbol = symbol
        self.theme = theme
        self.order = order
        self.profileId = profileId
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileId = try container.required(UUID.self, forKey: .profileId)
        name = container.lenient(String.self, forKey: .name) ?? ""
        symbol = container.lenient(String.self, forKey: .symbol) ?? SidebarIcon.defaultSpaceSymbol
        theme = container.lenient(SpaceTheme.self, forKey: .theme).map { SpaceTheme(name: $0.name, colors: $0.colors, angle: $0.angle) }
        order = container.order(forKey: .order)
    }
}

/// Fields of a folder of pinned tabs: `icon` as in `FolderRecord.iconValue`, colors as “#RRGGBB”.
nonisolated struct SyncFolderFields: Codable, Equatable, Sendable {
    var name: String
    var order: Double
    var isCollapsed: Bool
    var spaceId: UUID
    var parentId: UUID?
    var icon: String?
    var textColor: String?
    var backgroundColor: String?

    init(
        name: String,
        order: Double,
        isCollapsed: Bool,
        spaceId: UUID,
        parentId: UUID? = nil,
        icon: String? = nil,
        textColor: String? = nil,
        backgroundColor: String? = nil,
    ) {
        self.name = name
        self.order = order
        self.isCollapsed = isCollapsed
        self.spaceId = spaceId
        self.parentId = parentId
        self.icon = icon
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spaceId = try container.required(UUID.self, forKey: .spaceId)
        name = container.lenient(String.self, forKey: .name) ?? ""
        order = container.order(forKey: .order)
        isCollapsed = container.lenient(Bool.self, forKey: .isCollapsed) ?? false
        parentId = container.lenient(UUID.self, forKey: .parentId)
        icon = container.lenient(String.self, forKey: .icon)
        textColor = container.lenient(String.self, forKey: .textColor)
        backgroundColor = container.lenient(String.self, forKey: .backgroundColor)
    }
}

/// Placement of a synced tab; any other value makes the record ignored.
nonisolated enum SyncTabPlace: String, Codable, Sendable {
    case favorite
    case pinned
    case today
}

/// Fields of a tab (`SYNC.md` § 2.1 and § 2.4): original address and title of a favorite or a pinned tab, current
/// address and title of a today tab; `profileId` for a favorite, `spaceId` for the others. Only http and https
/// addresses travel: any other makes the record ignored.
nonisolated struct SyncTabFields: Codable, Equatable, Sendable {
    var place: SyncTabPlace
    var url: URL?
    var title: String?
    var order: Double
    var profileId: UUID?
    var spaceId: UUID?
    var folderId: UUID?
    /// Last use of a today tab; nil for the others.
    var lastActivity: Date?

    init(
        place: SyncTabPlace,
        url: URL?,
        title: String?,
        order: Double,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        folderId: UUID? = nil,
        lastActivity: Date? = nil,
    ) {
        self.place = place
        self.url = url
        self.title = title
        self.order = order
        self.profileId = profileId
        self.spaceId = spaceId
        self.folderId = folderId
        self.lastActivity = lastActivity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        place = try container.required(SyncTabPlace.self, forKey: .place)
        profileId = container.lenient(UUID.self, forKey: .profileId)
        spaceId = container.lenient(UUID.self, forKey: .spaceId)
        guard place == .favorite ? profileId != nil : spaceId != nil else {
            throw DecodingError.valueNotFound(UUID.self, .init(codingPath: decoder.codingPath, debugDescription: "Missing parent"))
        }
        if try !container.contains(.url) || container.decodeNil(forKey: .url) {
            url = nil
        } else {
            let address = try container.required(String.self, forKey: .url)
            guard let url = URL(string: address), SyncWebURL.isWeb(url) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a web address"))
            }
            self.url = url
        }
        title = container.lenient(String.self, forKey: .title)
        order = container.order(forKey: .order)
        folderId = container.lenient(UUID.self, forKey: .folderId)
        lastActivity = container.lenient(Date.self, forKey: .lastActivity)
    }

    /// True if `other` only differs by the address and the title of a today tab: a change that waits for the page to
    /// be stable before being sent (`SYNC.md` § 2.4).
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

    /// True if `other` only differs by the last use: not sent on its own (`SYNC.md` § 2.4).
    func differsOnlyByLastActivity(from other: SyncTabFields) -> Bool {
        var mine = self
        mine.lastActivity = other.lastActivity
        return mine == other && lastActivity != other.lastActivity
    }
}
