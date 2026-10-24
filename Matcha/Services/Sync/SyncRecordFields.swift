import Foundation

// Profiles, Spaces and folders with their synced fields, both ways side by side (audit C6): what is sent
// (`syncFields`, read by `MatchaSyncStore`) and what a received change writes (`apply`, called by `SyncRecordWriter`
// once the parents are found). Ranks are integers here and numbers in sync (`SyncOrder`). Tabs: `TabRecord+Sync`.

extension ProfileRecord {
    var syncFields: SyncProfileFields {
        SyncProfileFields(name: name, order: Double(order))
    }

    func apply(_ fields: SyncProfileFields) {
        name = fields.name
        order = SyncOrder.integer(fields.order)
    }
}

extension SpaceRecord {
    /// Nil for a Space outside any profile: it isn't sent.
    var syncFields: SyncSpaceFields? {
        guard let profileID = profile?.id else {
            return nil
        }
        return SyncSpaceFields(
            name: name,
            symbol: symbol,
            theme: SpaceTheme.decoded(from: themeData),
            order: Double(order),
            profileId: profileID,
        )
    }

    func apply(_ fields: SyncSpaceFields, profile newProfile: ProfileRecord) {
        name = fields.name
        symbol = SidebarIcon(spaceSymbol: fields.symbol).spaceSymbol
        themeData = fields.theme.flatMap { SpaceTheme(name: $0.name, colors: $0.colors, angle: $0.angle).encoded() }
        order = SyncOrder.integer(fields.order)
        profile = newProfile
    }
}

extension FolderRecord {
    /// Nil for a folder outside any Space: it isn't sent.
    var syncFields: SyncFolderFields? {
        guard let spaceID = space?.id else {
            return nil
        }
        return SyncFolderFields(
            name: name,
            order: Double(order),
            isCollapsed: isCollapsed,
            spaceId: spaceID,
            parentId: parent?.id,
            icon: iconValue,
            textColor: textColorHex,
            backgroundColor: backgroundColorHex,
        )
    }

    func apply(_ fields: SyncFolderFields, space newSpace: SpaceRecord, parent newParent: FolderRecord?) {
        name = fields.name
        order = SyncOrder.integer(fields.order)
        isCollapsed = fields.isCollapsed
        appearance = FolderAppearance(storedIcon: fields.icon, textColorHex: fields.textColor, backgroundColorHex: fields.backgroundColor)
        space = newSpace
        parent = newParent
    }
}
