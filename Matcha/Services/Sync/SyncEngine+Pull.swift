import Foundation
import OSLog

/// Reading the other Macs' changes and applying them on this Mac (`SYNC.md` § 5, step 2).
extension SyncEngine {
    /// Reads the changes since the cursor; if it expired, reads everything again.
    func pull() async throws {
        do {
            try await readChanges(from: state.cursor)
        } catch SyncTransportError.cursorExpired {
            Logger.sync.notice("Expired cursor: full reread")
            try await rereadEverything()
        }
    }

    /// Reads the pages since `cursor`, applying each one, then what was waiting for its parent; returns the
    /// identifiers read.
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
            try applyRemote(winners)
            cursor = page.cursor
            state.cursor = page.cursor
            save()
            if !page.hasMore {
                break
            }
        }
        try retryWaiting()
        return seen
    }

    /// Remembers `record`; true if it must be applied on this Mac: readable, newer than the content accepted here (no
    /// going back, `SYNC.md` § 2.3), and newer than this Mac's pending change.
    private func receive(_ record: SyncRemoteRecord) -> Bool {
        let id = record.id
        var entry = state.entries[id] ?? SyncEntry(type: record.content?.type ?? "")
        if let known = entry.version, record.version <= known {
            return false
        }
        entry.version = record.version
        guard let content = verified(record) else {
            Logger.sync.error("Unreadable record ignored")
            entry.isUnreadable = true
            state.entries[id] = entry
            return false
        }
        if let accepted = entry.remote, !content.isNewer(than: accepted) {
            // Not newer than what this Mac accepted: an older content replayed, ignored.
            if content != accepted {
                staleOnServer?.insert(id)
            }
            state.entries[id] = entry
            return false
        }
        observe(content)
        entry.type = content.type
        entry.remote = content
        entry.isUnreadable = false
        state.entries[id] = entry
        if let pending = state.pending[id] {
            guard content.isNewer(than: pending.content) || content.isFromNewerVersion else {
                // This Mac's change is newer: it will be sent again on top of this version.
                return false
            }
            state.pending[id] = nil
        }
        return true
    }

    /// Expired cursor: reads everything again, and never deletes on an absence (`SYNC.md` § 5). What this Mac has and
    /// the server lost, or has in an older version (restored backup), is sent again; when that is more than half of the
    /// account, the user chooses first.
    private func rereadEverything() async throws {
        state.cursor = nil
        staleOnServer = []
        let seen = try await readChanges(from: nil)
        let stale = staleOnServer ?? []
        staleOnServer = nil
        var missing: [UUID] = []
        for (id, entry) in state.entries where !seen.contains(id) {
            if state.pending[id] != nil {
                state.entries[id]?.version = nil
            } else if entry.local != nil, !entry.isIgnored {
                missing.append(id)
            } else {
                state.entries[id] = nil
            }
        }
        let resent = missing + stale.filter { state.pending[$0] == nil && state.entries[$0]?.local != nil }
        guard !resent.isEmpty else {
            return
        }
        let isMassive = resent.count >= Self.massChangeThreshold && resent.count * 2 > state.liveRecordCount + missing.count
        if isMassive, await confirmRecreations(resent.count) == .replaceLocal {
            let live = seen.filter { state.entries[$0]?.remote?.deleted == false && state.entries[$0]?.isUnreadable == false }
            try replaceLocalData(keeping: live)
            missing.forEach { state.entries[$0] = nil }
            return
        }
        Logger.sync.notice("Records unknown to the server sent again: \(resent.count, privacy: .public)")
        for id in resent {
            sendAgain(id, asCreation: missing.contains(id))
        }
        save()
    }

    /// Queues the last content accepted for `id` (or this Mac's fields), on top of the server's version or as a
    /// creation.
    private func sendAgain(_ id: UUID, asCreation: Bool) {
        guard let entry = state.entries[id], let local = entry.local else {
            return
        }
        if asCreation {
            state.entries[id]?.version = nil
        }
        if let accepted = entry.remote, !accepted.deleted {
            state.pending[id] = SyncPendingChange(content: accepted, local: local)
        } else if let type = SyncRecordType(rawValue: entry.type), let fields = SyncFields(json: local, type: type) {
            let content = SyncContent(fields: fields, modifiedAt: state.clock.next(now: now()), modifiedBy: state.deviceID)
            state.pending[id] = SyncPendingChange(content: content, local: local)
        }
    }

    /// Applies the accepted content of `ids` on this Mac. This Mac's fields after applying become the reference for
    /// the next changes: nothing is sent back as an echo. An unreadable record, or one from a newer version, is
    /// never applied.
    func applyRemote(_ ids: [UUID]) throws {
        var changes: [SyncLocalChange] = []
        for id in Set(ids) {
            guard let entry = state.entries[id], !entry.isUnreadable, let remote = entry.remote else {
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
                Logger.sync.notice("Record of an unknown format ignored")
            }
        }
        guard !changes.isEmpty else {
            return
        }
        let waiting = try store.apply(SyncLocalChange.ordered(changes))
        let snapshot = try store.snapshot()
        for change in changes {
            let isWaiting = waiting.contains(change.id)
            state.entries[change.id]?.isWaiting = isWaiting
            state.entries[change.id]?.local = isWaiting ? nil : snapshot[change.id]?.json
            if !isWaiting {
                report.received += 1
            }
        }
    }

    /// What was waiting for its parent: tried again once per read, after all the pages.
    func retryWaiting() throws {
        let waiting = state.entries.compactMap { $0.value.isWaiting ? $0.key : nil }
        if !waiting.isEmpty {
            try applyRemote(waiting)
        }
    }
}
