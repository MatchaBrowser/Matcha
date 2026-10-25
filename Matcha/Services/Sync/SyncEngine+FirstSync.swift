import Foundation
import OSLog

/// First sync of this Mac, or after a mode change (`SYNC.md` § 5).
extension SyncEngine {
    /// Types that “Replace This Mac's Data” removes when the synced data does not have them. Settings and extensions
    /// specific to this Mac stay, without being sent.
    static let replaceableTypes: Set<SyncRecordType> = [.profile, .space, .folder, .tab, .sitePermission, .siteZoom]

    /// Reads everything, chooses (nothing synced: send everything; this Mac only has its first-launch data: take the
    /// synced data; unreadable state file: merge; otherwise: ask), applies, then collects what remains to be sent.
    func firstSync() async throws {
        let (records, cursor) = try await readEverything()
        for record in records.values {
            var entry = SyncEntry(type: record.content?.type ?? "", version: record.version)
            if let content = verified(record) {
                observe(content)
                entry.type = content.type
                entry.remote = content
            } else {
                entry.isUnreadable = true
            }
            state.entries[record.id] = entry
        }
        let liveIDs = state.entries.compactMap { id, entry in
            !entry.isUnreadable && entry.remote?.deleted == false ? id : nil
        }
        let choice: FirstSyncChoice = if liveIDs.isEmpty {
            .replaceRemote
        } else if store.hasOnlyFirstLaunchData {
            .replaceLocal
        } else if state.mergesWithoutAsking {
            .merge
        } else {
            await chooseFirstSync()
        }
        Logger.sync.notice("First sync: \(String(describing: choice), privacy: .public)")
        switch choice {
        case .merge:
            try applyRemote(liveIDs)
        case .replaceLocal:
            try replaceLocalData(keeping: Set(liveIDs))
        case .replaceRemote:
            try replaceRemoteData(liveIDs: liveIDs)
        }
        try retryWaiting()
        state.cursor = cursor
        state.hasCompletedFirstSync = true
        state.mergesWithoutAsking = false
        save()
        // What this Mac has in addition: creations (on the server's version for an identifier derived from a key).
        try detectLocalChanges()
    }

    /// Every record of the account, and the cursor that follows them.
    private func readEverything() async throws -> (records: [UUID: SyncRemoteRecord], cursor: String?) {
        var records: [UUID: SyncRemoteRecord] = [:]
        var cursor: String?
        while true {
            let page = try await transport.changes(since: cursor)
            for record in page.records {
                records[record.id] = record
            }
            cursor = page.cursor
            if !page.hasMore {
                return (records, cursor)
            }
        }
    }

    /// Applies the synced data and removes from this Mac what it does not have; this Mac's local records (favorites
    /// and pinned tabs that aren't web addresses) aren't in the snapshot: they stay.
    func replaceLocalData(keeping liveIDs: Set<UUID>) throws {
        let before = try store.snapshot()
        try applyRemote(Array(liveIDs))
        var deletions: [SyncLocalChange] = []
        for (id, fields) in before where !liveIDs.contains(id) {
            if Self.replaceableTypes.contains(fields.type) {
                deletions.append(.delete(id, fields.type))
            } else if fields.type != .deviceTabs {
                // Kept on this Mac without being sent: its reference is its current state. This Mac's tabs leave as a
                // creation.
                var entry = state.entries[id] ?? SyncEntry(type: fields.type.rawValue)
                entry.local = fields.json
                state.entries[id] = entry
            }
        }
        _ = try store.apply(SyncLocalChange.ordered(deletions))
    }

    /// Queues the deletion of what is synced but not on this Mac, except the records it must never touch (unreadable,
    /// unknown type, newer format; the tabs of the other Macs and the today tabs of an older version: `SYNC.md` § 2.4);
    /// the rest of this Mac will be sent as creations, newer than everything that was read (`detectLocalChanges`).
    private func replaceRemoteData(liveIDs: [UUID]) throws {
        let local = try store.snapshot()
        for id in liveIDs where local[id] == nil {
            guard let entry = state.entries[id], !entry.isIgnored, let type = entry.remote?.recordType, type != .deviceTabs,
                  !SyncLegacyTodayTabs.isTodayTab(entry.remote?.fields, type: entry.type)
            else {
                continue
            }
            let deletion = SyncContent.deletion(
                of: type.rawValue,
                schema: type.schema,
                modifiedAt: state.clock.next(now: now(), after: entry.remote?.modifiedAt),
                modifiedBy: state.deviceID,
            )
            state.pending[id] = SyncPendingChange(content: deletion, local: nil)
        }
    }
}
