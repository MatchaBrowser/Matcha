import Foundation
import SwiftData

/// Deletions received from another Mac, applied from the content up to the parents (`SYNC.md` § 2.3): a deleted
/// folder's tabs and subfolders go back to the root of their Space; a deleted Space or profile takes its content
/// with it. Then `repair` restores what a batch can break: folder cycles, and a session without profile or Space.
extension SyncRecordWriter {
    func delete(_ id: UUID, _ type: SyncRecordType) {
        switch type {
        case .profile:
            deleteProfile(id)
        case .space:
            deleteSpace(id)
        case .folder:
            deleteFolder(id)
        case .tab:
            if let record = tabs.removeValue(forKey: id) {
                touch(record)
                context.delete(record)
            }
        case .setting, .sitePermission, .siteZoom:
            deletePreference(id, type)
        case .webExtension:
            deleteExtension(id)
        }
    }

    /// Folder cycles (A in B, B in A) are broken: the folder with the greatest identifier goes back to the root of its
    /// Space, the same choice on every Mac. A session left without profile or Space gets them back.
    func repair() {
        for folder in folders.values {
            var visited: Set<UUID> = [folder.id]
            var cycle = [folder]
            var parent = folder.parent
            while let current = parent, !visited.contains(current.id) {
                visited.insert(current.id)
                cycle.append(current)
                parent = current.parent
            }
            guard parent?.id == folder.id, let breaker = cycle.max(by: { $0.id.uuidString < $1.id.uuidString }) else {
                continue
            }
            breaker.parent = nil
            touch(breaker.space)
        }
        if session.ensureSyncDefaults(profileID: identifiers.defaultProfile, spaceID: identifiers.defaultSpace) {
            noteProfilesChanged()
        }
    }

    private func deleteFolder(_ id: UUID) {
        guard let record = folders.removeValue(forKey: id) else {
            return
        }
        touch(record.space)
        for child in record.children ?? [] {
            child.parent = nil
        }
        for tab in record.tabs ?? [] {
            tab.folder = nil
        }
        context.delete(record)
    }

    /// Setting, site decision or zoom: found by its identifier derived from a key. A deleted site decision only
    /// removes an `allow` here: going back to “Ask” elsewhere doesn't lift a refusal of this Mac (`SYNC.md` § 2.6).
    private func deletePreference(_ id: UUID, _ type: SyncRecordType) {
        switch type {
        case .setting:
            if let key = SyncedSettings.keys.first(where: { identifiers.setting($0) == id }) {
                defaults.removeObject(forKey: key)
            }
        case .sitePermission:
            let entry = session.sitePermissions.entries.first { entry in
                let key = entry.key
                return identifiers.sitePermission(profileID: key.profileID, origin: key.origin.key, kind: key.kind.rawValue) == id
            }
            if let entry, entry.decision == .allow {
                session.sitePermissions.set(nil, for: entry.key.kind, origin: entry.key.origin, profileID: entry.key.profileID)
            }
        case .siteZoom:
            if let site = session.siteZooms.levels.keys.first(where: { identifiers.siteZoom($0) == id }) {
                session.siteZooms.setLevel(ZoomLevels.actualSize, forSite: site)
            }
        default:
            break
        }
    }

    /// Uninstalled on another Mac: uninstalled here too, or no longer offered.
    private func deleteExtension(_ id: UUID) {
        guard let extensions else {
            return
        }
        let known = Array(extensions.fields().values) + Array(extensions.synced.offers.values)
        if let fields = known.first(where: { identifiers.webExtension($0) == id }) {
            extensions.remove(identifier: fields.identifier)
        }
    }

    private func deleteSpace(_ id: UUID) {
        if let space = session.spaces.first(where: { $0.id == id }) {
            session.removeSpaceFromSync(space)
            spaces[id] = nil
            changes.spaces = true
        } else if let record = spaces.removeValue(forKey: id) {
            context.delete(record)
        }
    }

    /// Its Spaces, favorites, decisions and history go with it; its website data afterwards (`SYNC.md` § 2.3).
    private func deleteProfile(_ id: UUID) {
        guard let profile = profiles[id] else {
            return
        }
        let spaceIDs = spaces.compactMap { $0.value.profile?.id == id ? $0.key : nil }
        guard let removed = session.removeProfile(profile, allowingLast: true) else {
            return
        }
        profiles[id] = nil
        spaceIDs.forEach { spaces[$0] = nil }
        noteProfilesChanged()
        Task { [session] in
            await session.removeWebsiteData(ofProfile: removed)
        }
    }
}
