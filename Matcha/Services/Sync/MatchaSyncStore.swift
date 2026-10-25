import Foundation
import SwiftData

/// Matcha's data as seen by sync (`SYNC.md` § 2.1): profiles, Spaces, folders, favorites and pinned tabs (SwiftData
/// records), site decisions, synced settings, site zoom, extensions, and this Mac's today tabs for the other Macs to
/// see. Received changes are written to the records (`SyncRecordWriter`), then the session picks them up
/// (`BrowserSession.reload`). A read failure throws.
@MainActor
final class MatchaSyncStore: SyncLocalStore {
    let session: BrowserSession
    let defaults: UserDefaults
    let identifiers: SyncIdentifiers
    /// Installed and offered extensions; nil: they do not travel (tests).
    let extensions: ExtensionSyncAdapter?
    /// This Mac, whose today tabs the others see (`deviceTabs`); nil: they don't travel (tests).
    let device: SyncDeviceDescription?
    /// False while signing out: the next cycle sends the deletion of this Mac's tabs (`SYNC.md` § 2.4).
    var publishesDeviceTabs = true

    init(
        session: BrowserSession,
        defaults: UserDefaults,
        identifiers: SyncIdentifiers,
        extensions: ExtensionSyncAdapter? = nil,
        device: SyncDeviceDescription? = nil,
    ) {
        self.session = session
        self.defaults = defaults
        self.identifiers = identifiers
        self.extensions = extensions
        self.device = device
    }

    func snapshot() throws -> [UUID: SyncFields] {
        var result: [UUID: SyncFields] = [:]
        for profile in try fetch(ProfileRecord.self) {
            result[profile.id] = .profile(profile.syncFields)
        }
        for space in try fetch(SpaceRecord.self) {
            if let fields = space.syncFields {
                result[space.id] = .space(fields)
            }
        }
        for folder in try fetch(FolderRecord.self) {
            if let fields = folder.syncFields {
                result[folder.id] = .folder(fields)
            }
        }
        let tabs = try fetch(TabRecord.self)
        for tab in tabs where !tab.isLocalOnly {
            if let fields = tab.syncFields {
                result[tab.id] = .tab(fields)
            }
        }
        addPreferences(to: &result)
        try addDeviceTabs(tabs.filter { $0.place == .today }, to: &result)
        return result
    }

    /// This Mac's today tabs, by Space in sidebar order, read-only for the other Macs (`SYNC.md` § 2.4).
    private func addDeviceTabs(_ today: [TabRecord], to result: inout [UUID: SyncFields]) throws {
        guard let device, publishesDeviceTabs else {
            return
        }
        let bySpace = Dictionary(grouping: today) { $0.space?.id }
        let spaces = try fetch(SpaceRecord.self).sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
        let local = spaces.map { space in
            let tabs = (bySpace[space.id] ?? []).sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
            return SyncDeviceTabsFields.LocalSpace(id: space.id, name: space.name, tabs: tabs.map { ($0.url, $0.title) })
        }
        let fields = SyncDeviceTabsFields.publishing(deviceId: device.id, name: device.name, spaces: local)
        result[identifiers.deviceTabs(device.id)] = .deviceTabs(fields)
    }

    /// Favorites and pinned tabs whose original address isn't a web address stay on this Mac (`SYNC.md` § 5).
    func exceptions() throws -> SyncLocalExceptions {
        var exceptions = SyncLocalExceptions()
        for tab in try fetch(TabRecord.self) where tab.isLocalOnly {
            exceptions.localRecords.insert(tab.id)
        }
        return exceptions
    }

    /// Site decisions, settings, zoom levels and extensions.
    private func addPreferences(to result: inout [UUID: SyncFields]) {
        for entry in session.sitePermissions.entries where entry.key.origin.isWeb {
            let key = entry.key
            guard let profileID = key.profileID else {
                continue
            }
            let id = identifiers.sitePermission(profileID: profileID, origin: key.origin.key, kind: key.kind.rawValue)
            result[id] = .sitePermission(SyncSitePermissionFields(
                origin: key.origin.key,
                kind: key.kind.rawValue,
                decision: entry.decision.rawValue,
                profileId: profileID,
            ))
        }
        for key in SyncedSettings.keys {
            if let object = defaults.object(forKey: key), let value = SyncedSettings.value(object, for: key) {
                result[identifiers.setting(key)] = .setting(SyncSettingFields(key: key, value: value))
            }
        }
        for (site, level) in session.siteZooms.levels {
            result[identifiers.siteZoom(site)] = .siteZoom(SyncSiteZoomFields(site: site, level: level))
        }
        for fields in (extensions?.fields() ?? [:]).values {
            result[identifiers.webExtension(fields)] = .webExtension(fields)
        }
    }

    func prepare(using transport: any SyncTransport) async {
        extensions?.transport = transport
        await extensions?.preparePackages(using: transport)
    }

    func finish(using transport: any SyncTransport, recordsSent: Bool) async {
        await extensions?.deleteObsoletePackages(using: transport, recordsSent: recordsSent)
    }

    func takeAdoptedRecords() -> Set<UUID> {
        guard let extensions else {
            return []
        }
        let adopted = extensions.takeAdopted()
        guard !adopted.isEmpty else {
            return []
        }
        let fields = extensions.fields()
        return Set(adopted.compactMap { fields[$0].map(identifiers.webExtension) })
    }

    func apply(_ changes: [SyncLocalChange]) throws -> Set<UUID> {
        // What is not saved yet (less than a second old) is saved first: nothing is lost when reloading.
        session.saveAll()
        let writer = try SyncRecordWriter(session: session, defaults: defaults, identifiers: identifiers, extensions: extensions)
        var waiting: Set<UUID> = []
        for change in changes {
            switch change {
            case let .upsert(id, fields):
                if !writer.upsert(id, fields) {
                    waiting.insert(id)
                }
            case let .delete(id, type):
                writer.delete(id, type)
            }
        }
        writer.repair()
        session.save(session.container.mainContext)
        session.reload(after: writer.changes)
        // The displayed tabs that sync did not change are saved as they are: they are not sent again.
        session.saveAll()
        return waiting
    }

    /// “Personal” profile and “Home” Space from the first launch, with no folder, favorite or pinned tab, and at most
    /// one empty today tab.
    var hasOnlyFirstLaunchData: Bool {
        guard let profiles = try? fetch(ProfileRecord.self), let spaces = try? fetch(SpaceRecord.self),
              let folders = try? fetch(FolderRecord.self), let tabs = try? fetch(TabRecord.self), profiles.count == 1, spaces.count == 1,
              folders.isEmpty,
              profiles[0].name == BrowserSession.defaultProfileName, spaces[0].name == BrowserSession.defaultSpaceName
        else {
            return false
        }
        let placed = tabs.filter { $0.place != nil }
        return placed.count <= 1 && placed.allSatisfy { $0.place == .today && $0.url == nil }
    }

    private func fetch<Model: PersistentModel>(_: Model.Type) throws -> [Model] {
        try session.container.mainContext.fetch(FetchDescriptor<Model>())
    }
}
