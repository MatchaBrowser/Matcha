import Foundation
import SwiftData

/// Suppressions reçues d'un autre Mac (tâche 7.4), appliquées du contenu vers les parents. Le dernier profil et le
/// dernier Space ne sont jamais supprimés.
extension SyncRecordWriter {
    func delete(_ id: UUID, _ type: SyncRecordType) {
        switch type {
        case .profile:
            deleteProfile(id)
        case .space:
            deleteSpace(id)
        case .folder:
            if let record = folders.removeValue(forKey: id) {
                touch(record.space)
                context.delete(record)
            }
        case .tab:
            if let record = tabs.removeValue(forKey: id) {
                touch(record)
                context.delete(record)
            }
        case .setting, .sitePermission, .siteZoom:
            deletePreference(id, type)
        case .webExtension:
            if let extensions {
                let known = extensions.manager.installedIdentifiers + extensions.synced.offers.keys
                if let identifier = known.first(where: { SyncIdentifier.webExtension($0) == id }) {
                    extensions.remove(identifier: identifier)
                }
            }
        }
    }

    /// Réglage, décision de site ou zoom : retrouvé par son identifiant tiré d'une clé.
    private func deletePreference(_ id: UUID, _ type: SyncRecordType) {
        switch type {
        case .setting:
            if let key = SyncedSettings.keys.first(where: { SyncIdentifier.setting($0) == id }) {
                defaults.removeObject(forKey: key)
            }
        case .sitePermission:
            let entry = session.sitePermissions.entries.first { entry in
                let key = entry.key
                return SyncIdentifier.sitePermission(profileID: key.profileID, origin: key.origin.key, kind: key.kind.rawValue) == id
            }
            if let key = entry?.key {
                session.sitePermissions.set(nil, for: key.kind, origin: key.origin, profileID: key.profileID)
            }
        case .siteZoom:
            if let site = session.siteZooms.levels.keys.first(where: { SyncIdentifier.siteZoom($0) == id }) {
                session.siteZooms.setLevel(ZoomLevels.actualSize, forSite: site)
            }
        default:
            break
        }
    }

    private func deleteSpace(_ id: UUID) {
        if let space = session.spaces.first(where: { $0.id == id }) {
            let count = session.spaces.count
            session.deleteSpace(space)
            if session.spaces.count < count {
                spaces[id] = nil
            }
        } else if let record = spaces.removeValue(forKey: id) {
            context.delete(record)
        }
    }

    /// Ses Spaces, favoris, décisions et historique partent avec lui ; ses données de sites ensuite.
    private func deleteProfile(_ id: UUID) {
        guard let profile = profiles[id], let removed = session.removeProfile(profile) else {
            return
        }
        profiles[id] = nil
        noteProfilesChanged()
        Task { [session] in
            await session.removeWebsiteData(ofProfile: removed)
        }
    }
}
