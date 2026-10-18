import Foundation
import OSLog

/// Première synchro de ce Mac, ou après un changement de mode (`SYNC.md` § 5).
extension SyncEngine {
    /// Types que « Remplacer les données de ce Mac » retire quand les données synchronisées ne les ont pas. Les
    /// réglages et les extensions propres à ce Mac restent, sans partir.
    static let replaceableTypes: Set<SyncRecordType> = [.profile, .space, .folder, .tab, .sitePermission, .siteZoom]

    /// Lit tout, choisit (rien de synchronisé : tout envoyer ; ce Mac n'a que son premier lancement : prendre les
    /// données synchronisées ; sinon : demander), applique, puis relève ce qui reste à envoyer.
    func firstSync() async throws {
        var remote: [UUID: SyncRemoteRecord] = [:]
        var cursor: String?
        while true {
            let page = try await transport.changes(since: cursor)
            for record in page.records {
                remote[record.id] = record
            }
            cursor = page.cursor
            if !page.hasMore {
                break
            }
        }
        for record in remote.values {
            state.entries[record.id] = SyncEntry(type: record.content?.type ?? "", version: record.version, remote: record.content)
            if let content = record.content {
                state.clock.observe(content.modifiedAt)
            }
        }
        let liveIDs = remote.values.compactMap { $0.content?.deleted == false ? $0.id : nil }
        let choice: FirstSyncChoice = if liveIDs.isEmpty {
            .replaceRemote
        } else if store.hasOnlyFirstLaunchData {
            .replaceLocal
        } else {
            await chooseFirstSync()
        }
        Logger.sync.notice("Première synchro : \(String(describing: choice), privacy: .public)")
        switch choice {
        case .merge:
            applyRemote(liveIDs)
        case .replaceLocal:
            replaceLocalData(keeping: Set(liveIDs))
        case .replaceRemote:
            replaceRemoteData(liveIDs: liveIDs)
        }
        state.cursor = cursor
        state.hasCompletedFirstSync = true
        save()
        // Ce que ce Mac a de plus : des créations (sur la version du serveur pour un identifiant tiré d'une clé).
        detectLocalChanges()
    }

    /// Applique les données synchronisées et retire de ce Mac ce qu'elles n'ont pas.
    private func replaceLocalData(keeping liveIDs: Set<UUID>) {
        let before = store.snapshot()
        applyRemote(Array(liveIDs))
        var deletions: [SyncLocalChange] = []
        for (id, fields) in before where !liveIDs.contains(id) {
            if Self.replaceableTypes.contains(fields.type) {
                deletions.append(.delete(id, fields.type))
            } else {
                // Gardé sur ce Mac sans partir : sa référence est son état actuel.
                var entry = state.entries[id] ?? SyncEntry(type: fields.type.rawValue)
                entry.local = fields.json
                state.entries[id] = entry
            }
        }
        _ = store.apply(SyncLocalChange.ordered(deletions))
    }

    /// Met en attente la suppression de ce qui est synchronisé sans être sur ce Mac ; le reste de ce Mac partira comme
    /// des créations, plus récentes que tout ce qui a été lu (`detectLocalChanges`).
    private func replaceRemoteData(liveIDs: [UUID]) {
        let local = store.snapshot()
        for id in liveIDs where local[id] == nil {
            guard let entry = state.entries[id] else {
                continue
            }
            let schema = SyncRecordType(rawValue: entry.type)?.schema ?? 1
            let deletion = SyncContent.deletion(
                of: entry.type,
                schema: schema,
                modifiedAt: state.clock.next(now: now()),
                modifiedBy: state.deviceID,
            )
            state.pending[id] = SyncPendingChange(content: deletion, local: nil)
        }
    }
}
