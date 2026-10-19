import Foundation
import OSLog

/// Reading the other Macs' changes and applying them on this Mac (`SYNC.md` § 5, step 2).
extension SyncEngine {
    /// Reads the changes since the cursor; if it expired, reads everything again.
    func pull() async throws {
        do {
            try await readChanges(from: state.cursor)
        } catch SyncTransportError.cursorExpired {
            Logger.sync.notice("Curseur expiré : relecture complète")
            try await rereadEverything()
        }
    }

    /// Reads the pages since `cursor`, applying each one; returns the identifiers read.
    @discardableResult
    func readChanges(from cursor: String?) async throws -> Set<UUID> {
        var cursor = cursor
        var seen: Set<UUID> = []
        while true {
            let page = try await transport.changes(since: cursor)
            var winners: [UUID] = []
            for record in page.records {
                seen.insert(record.id)
                if receive(record) {
                    winners.append(record.id)
                }
            }
            applyRemote(winners)
            cursor = page.cursor
            state.cursor = page.cursor
            save()
            if !page.hasMore {
                return seen
            }
        }
    }

    /// Remembers `record`; true if it must be applied on this Mac (not an echo of this Mac nor an outdated version,
    /// not older than its pending change).
    private func receive(_ record: SyncRemoteRecord) -> Bool {
        var entry = state.entries[record.id] ?? SyncEntry(type: record.content?.type ?? "")
        if let known = entry.version, record.version <= known {
            return false
        }
        entry.version = record.version
        guard let content = record.content else {
            Logger.sync.error("Enregistrement illisible ignoré")
            state.entries[record.id] = entry
            return false
        }
        state.clock.observe(content.modifiedAt)
        entry.type = content.type
        entry.remote = content
        state.entries[record.id] = entry
        if let pending = state.pending[record.id] {
            guard content.isNewer(than: pending.content) || content.isFromNewerVersion else {
                // This Mac's change is newer: it will be sent again on top of this version.
                return false
            }
            state.pending[record.id] = nil
        }
        return true
    }

    /// Expired cursor: reads everything again; a record of this Mac that is missing from the server and has no pending
    /// change is deleted here.
    private func rereadEverything() async throws {
        state.cursor = nil
        let seen = try await readChanges(from: nil)
        var deletions: [SyncLocalChange] = []
        for (id, entry) in state.entries where !seen.contains(id) {
            if state.pending[id] != nil {
                state.entries[id]?.version = nil
                continue
            }
            if entry.local != nil, let type = SyncRecordType(rawValue: entry.type) {
                deletions.append(.delete(id, type))
            }
            state.entries[id] = nil
        }
        _ = store.apply(SyncLocalChange.ordered(deletions))
        report.received += deletions.count
    }

    /// Applies the server's content of `ids` on this Mac, and retries what was waiting for its parent. This Mac's
    /// fields after applying become the reference for the next changes: nothing is sent back as an echo.
    func applyRemote(_ ids: [UUID]) {
        let retried = state.entries.compactMap { $0.value.isWaiting ? $0.key : nil }
        var changes: [SyncLocalChange] = []
        for id in Set(ids).union(retried) {
            guard let remote = state.entries[id]?.remote else {
                continue
            }
            if remote.deleted {
                if let type = remote.recordType {
                    changes.append(.delete(id, type))
                }
            } else if let fields = remote.readableFields {
                changes.append(.upsert(id, fields))
            } else {
                // Unknown type, format or value: ignored, without overwriting what this Mac has.
                Logger.sync.notice("Enregistrement d'un format inconnu ignoré")
            }
        }
        guard !changes.isEmpty else {
            return
        }
        let waiting = store.apply(SyncLocalChange.ordered(changes))
        let snapshot = store.snapshot()
        for change in changes {
            let isWaiting = waiting.contains(change.id)
            state.entries[change.id]?.isWaiting = isWaiting
            state.entries[change.id]?.local = isWaiting ? nil : snapshot[change.id]?.json
            if !isWaiting {
                report.received += 1
            }
        }
    }
}
