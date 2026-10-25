import Foundation
import SwiftData

/// Writes the changes received from another Mac to the records, the settings, the site decisions and the site zoom,
/// and notes what changed so the session picks it up (`BrowserSession.reload`). A record whose parent is missing is not
/// written (`upsert` returns false): it waits for its parent. A folder of another Space is not a parent: `spaceId`
/// prevails, and the tab or the folder goes back to the root of its Space (`SYNC.md` § 2.3).
@MainActor
final class SyncRecordWriter {
    let session: BrowserSession
    let defaults: UserDefaults
    let identifiers: SyncIdentifiers
    let extensions: ExtensionSyncAdapter?
    let context: ModelContext
    var profiles: [UUID: ProfileRecord]
    var spaces: [UUID: SpaceRecord]
    var folders: [UUID: FolderRecord]
    var tabs: [UUID: TabRecord]
    var changes = BrowserSession.SyncChanges()

    init(session: BrowserSession, defaults: UserDefaults, identifiers: SyncIdentifiers, extensions: ExtensionSyncAdapter?) throws {
        self.session = session
        self.defaults = defaults
        self.identifiers = identifiers
        self.extensions = extensions
        context = session.container.mainContext
        profiles = try Self.byID(context.fetch(FetchDescriptor<ProfileRecord>()), id: \.id)
        spaces = try Self.byID(context.fetch(FetchDescriptor<SpaceRecord>()), id: \.id)
        folders = try Self.byID(context.fetch(FetchDescriptor<FolderRecord>()), id: \.id)
        tabs = try Self.byID(context.fetch(FetchDescriptor<TabRecord>()), id: \.id)
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
            if let value = SyncedSettings.defaultsValue(of: fields.value) {
                defaults.set(value, forKey: fields.key)
            }
            return true
        case let .sitePermission(fields):
            return upsertPermission(fields)
        case let .siteZoom(fields):
            session.siteZooms.setLevel(fields.level, forSite: fields.site)
            return true
        case let .webExtension(fields):
            extensions?.apply(fields)
            return true
        case .deviceTabs:
            // Never applied: shown as received, from the sync state (`OtherMacsTabs`, `SYNC.md` § 2.4).
            return true
        }
    }

    // MARK: Profiles, Spaces, folders

    private func upsertProfile(_ id: UUID, _ fields: SyncProfileFields) {
        let record = profiles[id] ?? inserted(ProfileRecord(id: id, name: fields.name)) { profiles[id] = $0 }
        record.apply(fields)
        changes.profiles = true
    }

    private func upsertSpace(_ id: UUID, _ fields: SyncSpaceFields) -> Bool {
        guard let profile = profiles[fields.profileId] else {
            return false
        }
        let record = spaces[id] ?? inserted(SpaceRecord(id: id, name: fields.name)) { spaces[id] = $0 }
        record.apply(fields, profile: profile)
        changes.spaces = true
        return true
    }

    private func upsertFolder(_ id: UUID, _ fields: SyncFolderFields) -> Bool {
        guard let space = spaces[fields.spaceId] else {
            return false
        }
        var parent: FolderRecord?
        if let parentID = fields.parentId {
            guard let found = folders[parentID] else {
                return false
            }
            parent = found.space?.id == space.id ? found : nil
        }
        let record = folders[id] ?? inserted(FolderRecord(id: id, name: fields.name)) { folders[id] = $0 }
        touch(record.space)
        record.apply(fields, space: space, parent: parent)
        touch(space)
        return true
    }

    // MARK: Tabs

    /// The tab is written once its profile (favorite) or its Space, and its folder, are found (`TabRecord.apply`).
    private func upsertTab(_ id: UUID, _ fields: SyncTabFields) -> Bool {
        // A today tab of an older version (`SYNC.md` § 2.4): ignored, even for a favorite or a pinned tab of this Mac.
        guard fields.place != .today else {
            return true
        }
        let place = fields.place.tabPlace
        let profile = place == .favorite ? fields.profileId.flatMap { profiles[$0] } : nil
        let space = place == .favorite ? nil : fields.spaceId.flatMap { spaces[$0] }
        guard profile != nil || space != nil else {
            return false
        }
        var folder: FolderRecord?
        if place == .pinned, let folderID = fields.folderId {
            guard let found = folders[folderID] else {
                return false
            }
            folder = found.space?.id == space?.id ? found : nil
        }
        let existing = tabs[id]
        let record = existing ?? inserted(TabRecord(id: id, url: fields.url, title: fields.title, place: place)) { tabs[id] = $0 }
        touch(record)
        record.apply(fields, isNew: existing == nil, folder: folder, profile: profile, space: space)
        touch(record)
        return true
    }

    /// Only refusals apply (`SYNC.md` § 2.6): a received `deny` replaces this Mac's decision; a received `allow` opens
    /// nothing, this Mac keeps asking.
    private func upsertPermission(_ fields: SyncSitePermissionFields) -> Bool {
        guard profiles[fields.profileId] != nil else {
            return false
        }
        guard fields.decision == SitePermissionDecision.deny.rawValue, let origin = SiteOrigin(key: fields.origin),
              let kind = SitePermissionKind(rawValue: fields.kind)
        else {
            return true
        }
        session.sitePermissions.set(.deny, for: kind, origin: origin, profileID: fields.profileId)
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

    func inserted<Model: PersistentModel>(_ model: Model, register: (Model) -> Void) -> Model {
        context.insert(model)
        register(model)
        return model
    }

    private static func byID<Model>(_ models: [Model], id: (Model) -> UUID) -> [UUID: Model] {
        Dictionary(models.map { (id($0), $0) }) { first, _ in first }
    }
}
