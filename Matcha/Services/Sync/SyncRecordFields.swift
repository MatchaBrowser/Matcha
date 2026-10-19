import Foundation

// Profiles, Spaces and folders with their synced fields, both ways side by side (audit C6): what is sent
// (`syncFields`, read by `MatchaSyncStore`) and what a received change writes (`apply`, called by `SyncRecordWriter`
// once the parents are found). Tabs: `TabRecord+Sync`.

extension ProfileRecord {
    var syncFields: SyncProfileFields {
        SyncProfileFields(name: name, order: order)
    }

    func apply(_ fields: SyncProfileFields) {
        name = fields.name
        order = fields.order
    }
}

extension SpaceRecord {
    var syncFields: SyncSpaceFields {
        SyncSpaceFields(name: name, symbol: symbol, theme: SpaceTheme.decoded(from: themeData), order: order, profileId: profile?.id)
    }

    func apply(_ fields: SyncSpaceFields, profile newProfile: ProfileRecord?) {
        name = fields.name
        symbol = SidebarIcon(spaceSymbol: fields.symbol).spaceSymbol
        themeData = fields.theme.flatMap { SpaceTheme(name: $0.name, colors: $0.colors, angle: $0.angle).encoded() }
        order = fields.order
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
            order: order,
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
        order = fields.order
        isCollapsed = fields.isCollapsed
        appearance = FolderAppearance(storedIcon: fields.icon, textColorHex: fields.textColor, backgroundColorHex: fields.backgroundColor)
        space = newSpace
        parent = newParent
    }
}
