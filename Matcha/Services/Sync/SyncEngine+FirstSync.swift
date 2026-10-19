import Foundation
import OSLog

/// First sync of this Mac, or after a mode change (`SYNC.md` § 5).
extension SyncEngine {
    /// Types that “Replace This Mac's Data” removes when the synced data does not have them. Settings and extensions
    /// specific to this Mac stay, without being sent.
    static let replaceableTypes: Set<SyncRecordType> = [.profile, .space, .folder, .tab, .sitePermission, .siteZoom]

    /// Reads everything, chooses (nothing synced: send everything; this Mac only has its first-launch data: take the
    /// synced data; otherwise: ask), applies, then collects what remains to be sent.
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
        Logger.sync.notice("First sync: \(String(describing: choice), privacy: .public)")
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
        // What this Mac has in addition: creations (on the server's version for an identifier derived from a key).
        detectLocalChanges()
    }

    /// Applies the synced data and removes from this Mac what it does not have.
    private func replaceLocalData(keeping liveIDs: Set<UUID>) {
        let before = store.snapshot()
        applyRemote(Array(liveIDs))
        var deletions: [SyncLocalChange] = []
        for (id, fields) in before where !liveIDs.contains(id) {
            if Self.replaceableTypes.contains(fields.type) {
                deletions.append(.delete(id, fields.type))
            } else {
                // Kept on this Mac without being sent: its reference is its current state.
                var entry = state.entries[id] ?? SyncEntry(type: fields.type.rawValue)
                entry.local = fields.json
                state.entries[id] = entry
            }
        }
        _ = store.apply(SyncLocalChange.ordered(deletions))
    }

    /// Queues the deletion of what is synced but not on this Mac; the rest of this Mac will be sent as creations,
    /// newer than everything that was read (`detectLocalChanges`).
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
