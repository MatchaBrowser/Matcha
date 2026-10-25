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
            try applyAccepted(winners)
            cursor = page.cursor
            state.cursor = page.cursor
            save()
            if !page.hasMore {
                break
            }
        }
        try retryWaiting(after: seen)
        return seen
    }

    /// Remembers `record`; true if it must be applied on this Mac: readable, newer than the content accepted here (no
    /// going back, `SYNC.md` § 2.3), and newer than this Mac's pending change.
    private func receive(_ record: SyncRemoteRecord) -> Bool {
        let id = record.id
        var entry = state.entries[id] ?? SyncEntry(type: record.content?.type ?? "")
        // During a full reread, an older version is read too: a restored server has it (review SY10).
        if staleOnServer == nil, let known = entry.version, record.version <= known {
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
        // A deletion the restored server lost is sent again too (review SY10).
        let resent = missing + stale.filter { id in
            state.pending[id] == nil && (state.entries[id]?.local != nil || state.entries[id]?.remote?.deleted == true)
        }
        guard !resent.isEmpty else {
            return
        }
        let isMassive = resent.count >= Self.massChangeThreshold && resent.count * 2 > state.liveRecordCount + missing.count
        let choice = isMassive ? await confirmRecreations(resent.count) : .sendAgain
        try Task.checkCancellation()
        if choice == .replaceLocal {
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
        guard let entry = state.entries[id] else {
            return
        }
        if let accepted = entry.remote, accepted.deleted {
            state.pending[id] = SyncPendingChange(content: accepted, local: nil)
            return
        }
        guard let local = entry.local else {
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
}
