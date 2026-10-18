import Foundation
import SwiftData

/// Données de Matcha vues par la synchro (tâche 7.4, `SYNC.md` § 2.1) : profils, Spaces, dossiers et onglets
/// (enregistrements SwiftData), décisions de site, réglages synchronisés et zoom des sites. Les changements reçus sont
/// écrits dans les enregistrements (`SyncRecordWriter`), puis la session les reprend (`BrowserSession.reload`).
@MainActor
final class MatchaSyncStore: SyncLocalStore {
    let session: BrowserSession
    let defaults: UserDefaults
    /// Extensions installées et proposées ; nil : elles ne voyagent pas (tests).
    let extensions: ExtensionSyncAdapter?

    init(session: BrowserSession, defaults: UserDefaults, extensions: ExtensionSyncAdapter? = nil) {
        self.session = session
        self.defaults = defaults
        self.extensions = extensions
    }

    func snapshot() -> [UUID: SyncFields] {
        var result: [UUID: SyncFields] = [:]
        for profile in fetch(ProfileRecord.self) {
            result[profile.id] = .profile(SyncProfileFields(name: profile.name, order: profile.order))
        }
        for space in fetch(SpaceRecord.self) {
            result[space.id] = .space(SyncSpaceFields(
                name: space.name,
                symbol: space.symbol,
                theme: SpaceTheme.decoded(from: space.themeData),
                order: space.order,
                profileId: space.profile?.id,
            ))
        }
        for folder in fetch(FolderRecord.self) {
            if let fields = Self.fields(of: folder) {
                result[folder.id] = .folder(fields)
            }
        }
        for tab in fetch(TabRecord.self) {
            if let fields = Self.fields(of: tab) {
                result[tab.id] = .tab(fields)
            }
        }
        addPreferences(to: &result)
        return result
    }

    /// Décisions de site, réglages, zooms et extensions.
    private func addPreferences(to result: inout [UUID: SyncFields]) {
        for entry in session.sitePermissions.entries {
            let key = entry.key
            let id = SyncIdentifier.sitePermission(profileID: key.profileID, origin: key.origin.key, kind: key.kind.rawValue)
            result[id] = .sitePermission(SyncSitePermissionFields(
                origin: key.origin.key,
                kind: key.kind.rawValue,
                decision: entry.decision.rawValue,
                profileId: key.profileID,
            ))
        }
        for key in SyncedSettings.keys {
            if let object = defaults.object(forKey: key), let value = SyncedSettings.value(object, for: key) {
                result[SyncIdentifier.setting(key)] = .setting(SyncSettingFields(key: key, value: value))
            }
        }
        for (site, level) in session.siteZooms.levels {
            result[SyncIdentifier.siteZoom(site)] = .siteZoom(SyncSiteZoomFields(site: site, level: level))
        }
        for (identifier, fields) in extensions?.fields() ?? [:] {
            result[SyncIdentifier.webExtension(identifier)] = .webExtension(fields)
        }
    }

    func prepare(using transport: any SyncTransport) async {
        extensions?.transport = transport
        await extensions?.preparePackages(using: transport)
    }

    func finish(using transport: any SyncTransport) async {
        await extensions?.deleteObsoletePackages(using: transport)
    }

    func apply(_ changes: [SyncLocalChange]) -> Set<UUID> {
        // Ce qui n'est pas encore enregistré (moins d'une seconde) l'est d'abord : rien ne se perd à la reprise.
        session.saveAll()
        let writer = SyncRecordWriter(session: session, defaults: defaults, extensions: extensions)
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
        session.save(session.container.mainContext)
        session.reload(after: writer.changes)
        // Les onglets affichés que la synchro n'a pas changés sont enregistrés tels quels : ils ne repartent pas.
        session.saveAll()
        return waiting
    }

    /// Profil « Personnel » et Space « Perso » du premier lancement, sans dossier, favori ni épinglé, et au plus un
    /// onglet du jour vide.
    var hasOnlyFirstLaunchData: Bool {
        let profiles = fetch(ProfileRecord.self)
        let spaces = fetch(SpaceRecord.self)
        guard profiles.count == 1, spaces.count == 1, fetch(FolderRecord.self).isEmpty,
              profiles[0].name == BrowserSession.defaultProfileName, spaces[0].name == BrowserSession.defaultSpaceName
        else {
            return false
        }
        let tabs = fetch(TabRecord.self).filter { $0.place != nil }
        return tabs.count <= 1 && tabs.allSatisfy { $0.place == .today && $0.url == nil }
    }

    // MARK: Champs

    private static func fields(of folder: FolderRecord) -> SyncFolderFields? {
        guard let spaceID = folder.space?.id else {
            return nil
        }
        return SyncFolderFields(
            name: folder.name,
            order: folder.order,
            isCollapsed: folder.isCollapsed,
            spaceId: spaceID,
            parentId: folder.parent?.id,
            icon: folder.iconValue,
            textColor: folder.textColorHex,
            backgroundColor: folder.backgroundColorHex,
        )
    }

    /// Favori et épinglé : adresse et titre d'origine ; onglet du jour : adresse, titre et dernière utilisation.
    private static func fields(of tab: TabRecord) -> SyncTabFields? {
        switch tab.place {
        case .favorite:
            guard let profileID = tab.profile?.id else {
                return nil
            }
            return SyncTabFields(
                place: .favorite,
                url: tab.pinnedURL ?? tab.url,
                title: tab.pinnedTitle ?? tab.title,
                order: tab.order,
                profileId: profileID,
            )
        case .pinned:
            guard let spaceID = tab.space?.id else {
                return nil
            }
            return SyncTabFields(
                place: .pinned,
                url: tab.pinnedURL ?? tab.url,
                title: tab.pinnedTitle ?? tab.title,
                order: tab.order,
                spaceId: spaceID,
                folderId: tab.folder?.id,
            )
        case .today:
            guard let spaceID = tab.space?.id else {
                return nil
            }
            return SyncTabFields(
                place: .today,
                url: tab.url,
                title: tab.title,
                order: tab.order,
                spaceId: spaceID,
                lastActivity: tab.lastActivity,
            )
        case nil:
            return nil
        }
    }

    private func fetch<Model: PersistentModel>(_: Model.Type) -> [Model] {
        (try? session.container.mainContext.fetch(FetchDescriptor<Model>())) ?? []
    }
}
