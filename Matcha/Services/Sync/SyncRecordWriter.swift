import Foundation
import SwiftData

/// Writes the changes received from another Mac (task 7.4) to the records, the settings and the site zoom, and notes
/// what changed so the session picks it up (`BrowserSession.reload`). A record whose parent is missing is not written
/// (`upsert` returns false): it waits for the next read.
@MainActor
final class SyncRecordWriter {
    let session: BrowserSession
    let defaults: UserDefaults
    let extensions: ExtensionSyncAdapter?
    let context: ModelContext
    var profiles: [UUID: ProfileRecord]
    var spaces: [UUID: SpaceRecord]
    var folders: [UUID: FolderRecord]
    var tabs: [UUID: TabRecord]
    private(set) var changes = BrowserSession.SyncChanges()

    init(session: BrowserSession, defaults: UserDefaults, extensions: ExtensionSyncAdapter?) {
        self.session = session
        self.defaults = defaults
        self.extensions = extensions
        context = session.container.mainContext
        profiles = Self.byID((try? context.fetch(FetchDescriptor<ProfileRecord>())) ?? [], id: \.id)
        spaces = Self.byID((try? context.fetch(FetchDescriptor<SpaceRecord>())) ?? [], id: \.id)
        folders = Self.byID((try? context.fetch(FetchDescriptor<FolderRecord>())) ?? [], id: \.id)
        tabs = Self.byID((try? context.fetch(FetchDescriptor<TabRecord>())) ?? [], id: \.id)
    }

    /// Creates or modifies `id`; false if its parent is missing.
    func upsert(_ id: UUID, _ fields: SyncFields) -> Bool {
        switch fields {
        case let .profile(fields):
            upsertProfile(id, fields)
            return true
        case let .space(fields):
            return upsertSpace(id, fields)
        case let .folder(fields):
            return upsertFolder(id, fields)
        case let .tab(fields):
            return upsertTab(id, fields)
        case let .setting(fields):
            defaults.set(SyncedSettings.defaultsValue(of: fields.value), forKey: fields.key)
            return true
        case let .sitePermission(fields):
            return upsertPermission(fields)
        case let .siteZoom(fields):
            session.siteZooms.setLevel(fields.level, forSite: fields.site)
            return true
        case let .webExtension(fields):
            extensions?.apply(fields)
            return true
        }
    }

    // MARK: Profiles, Spaces, folders

    private func upsertProfile(_ id: UUID, _ fields: SyncProfileFields) {
        let record = profiles[id] ?? inserted(ProfileRecord(id: id, name: fields.name)) { profiles[id] = $0 }
        record.name = fields.name
        record.order = fields.order
        changes.profiles = true
    }

    private func upsertSpace(_ id: UUID, _ fields: SyncSpaceFields) -> Bool {
        let profile = fields.profileId.flatMap { profiles[$0] }
        guard fields.profileId == nil || profile != nil else {
            return false
        }
        let record = spaces[id] ?? inserted(SpaceRecord(id: id, name: fields.name)) { spaces[id] = $0 }
        record.name = fields.name
        record.symbol = SidebarIcon(spaceSymbol: fields.symbol).spaceSymbol
        record.themeData = fields.theme.flatMap { SpaceTheme(name: $0.name, colors: $0.colors, angle: $0.angle).encoded() }
        record.order = fields.order
        record.profile = profile
        changes.spaces = true
        return true
    }

    private func upsertFolder(_ id: UUID, _ fields: SyncFolderFields) -> Bool {
        let parent = fields.parentId.flatMap { folders[$0] }
        guard let space = fields.spaceId.flatMap({ spaces[$0] }), fields.parentId == nil || parent != nil else {
            return false
        }
        let record = folders[id] ?? inserted(FolderRecord(id: id, name: fields.name)) { folders[id] = $0 }
        touch(record.space)
        record.name = fields.name
        record.order = fields.order
        record.isCollapsed = fields.isCollapsed
        record.appearance = FolderAppearance(
            storedIcon: fields.icon,
            textColorHex: fields.textColor,
            backgroundColorHex: fields.backgroundColor,
        )
        record.space = space
        record.parent = parent
        touch(space)
        return true
    }

    // MARK: Tabs

    /// Favorite and pinned tab: their original address changes; their current address follows it if they had not left
    /// the old one. Today tab: its current address. An arriving tab will not select itself.
    private func upsertTab(_ id: UUID, _ fields: SyncTabFields) -> Bool {
        let place: TabPlace = switch fields.place {
        case .favorite: .favorite
        case .pinned: .pinned
        case .today: .today
        }
        let profile = place == .favorite ? fields.profileId.flatMap { profiles[$0] } : nil
        let space = place == .favorite ? nil : fields.spaceId.flatMap { spaces[$0] }
        let folder = place == .pinned ? fields.folderId.flatMap { folders[$0] } : nil
        guard profile != nil || space != nil, place != .pinned || fields.folderId == nil || folder != nil else {
            return false
        }
        let existing = tabs[id]
        let record = existing ?? inserted(TabRecord(id: id, url: fields.url, title: fields.title, place: place)) { tabs[id] = $0 }
        touch(record)
        if place == .today {
            record.pinnedURL = nil
            record.pinnedTitle = nil
            record.url = fields.url
            record.title = fields.title
            record.lastActivity = fields.lastActivity ?? record.lastActivity
        } else {
            let followsOrigin = existing == nil || record.place == .today || record.url == record.pinnedURL
            record.pinnedURL = fields.url
            record.pinnedTitle = fields.title
            if followsOrigin {
                record.url = fields.url
                record.title = fields.title
            }
            if existing == nil {
                record.lastActivity = .distantPast
            }
        }
        if record.place != place {
            record.splitGroupID = nil
            record.splitFraction = 0
        }
        record.place = place
        record.order = fields.order
        record.folder = folder
        record.profile = profile
        record.space = space
        touch(record)
        return true
    }

    private func upsertPermission(_ fields: SyncSitePermissionFields) -> Bool {
        guard fields.profileId.map({ profiles[$0] != nil }) ?? true else {
            return false
        }
        guard let origin = SiteOrigin(key: fields.origin), let kind = SitePermissionKind(rawValue: fields.kind),
              let decision = SitePermissionDecision(rawValue: fields.decision)
        else {
            return true
        }
        session.sitePermissions.set(decision, for: kind, origin: origin, profileID: fields.profileId)
        return true
    }

    // MARK: What changes

    /// The Space of `record`, or the favorites of its profile, need to be reloaded.
    func touch(_ record: TabRecord) {
        touch(record.space)
        if let profileID = record.profile?.id {
            changes.favorites.insert(profileID)
        }
    }

    func touch(_ space: SpaceRecord?) {
        if let id = space?.id {
            changes.spaceContents.insert(id)
        }
    }

    func noteProfilesChanged() {
        changes.profiles = true
        changes.spaces = true
    }

    private func inserted<Model: PersistentModel>(_ model: Model, register: (Model) -> Void) -> Model {
        context.insert(model)
        register(model)
        return model
    }

    private static func byID<Model>(_ models: [Model], id: (Model) -> UUID) -> [UUID: Model] {
        Dictionary(models.map { (id($0), $0) }) { first, _ in first }
    }
}
