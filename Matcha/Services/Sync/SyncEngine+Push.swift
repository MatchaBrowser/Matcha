import Foundation
import OSLog

/// Sending the pending changes (`SYNC.md` § 4.6 and § 5, step 1).
extension SyncEngine {
    /// Maximum number of sending rounds in a cycle: a conflict won by this Mac is sent again in the next round.
    static let pushRounds = 4

    private enum Outcome {
        case done
        /// The server has something newer: its content is applied here.
        case remoteWins
        /// To send again in the next round: this Mac has something newer, or the server no longer knows the record.
        case retry
    }

    /// The batch left without an answer (network error, restart) is sent again first, exactly as it was, with its
    /// key: a batch applied whose answer was lost would otherwise conflict with itself.
    func resendInFlight() async throws {
        guard !isSendingPaused, let inFlight = state.inFlight else {
            return
        }
        let winners = try await send(inFlight).winners
        try applyAccepted(winners)
        save()
    }

    /// Sends the pending changes, in batches, parents first; when the account is full, deletions first, in batches of
    /// their own, since they free space.
    func push() async throws {
        guard !isSendingPaused else {
            return
        }
        for _ in 0 ..< Self.pushRounds {
            let batches = pendingBatches()
            guard !batches.isEmpty else {
                return
            }
            var retries = false
            var queue = batches
            while !queue.isEmpty {
                let ids = queue.removeFirst()
                do {
                    let outcome = try await sendBatch(ids)
                    // Applied at once: a later batch that fails doesn't lose them (review SY6).
                    try applyAccepted(outcome.winners)
                    retries = retries || outcome.retries
                } catch SyncTransportError.batchTooLarge {
                    // Too big for one request: in two halves; a single change that is too big stays on this Mac.
                    state.inFlight = nil
                    if ids.count > 1 {
                        queue.insert(contentsOf: [Array(ids[..<(ids.count / 2)]), Array(ids[(ids.count / 2)...])], at: 0)
                    } else if let id = ids.first, let pending = state.pending.removeValue(forKey: id) {
                        state.rejected[id] = SyncRejection(code: SyncRejectionCode.payloadTooLarge, local: pending.local ?? .null)
                    }
                }
            }
            save()
            if !retries {
                return
            }
        }
    }

    /// Prepares the batch of `ids`, keeps it as the batch in flight, then sends it.
    private func sendBatch(_ ids: [UUID]) async throws -> (winners: [UUID], retries: Bool) {
        let outgoing = ids.compactMap { id in
            state.pending[id].map { SyncOutgoingChange(id: id, baseVersion: state.entries[id]?.version, content: $0.content) }
        }
        let sent = Dictionary(uniqueKeysWithValues: ids.compactMap { id in state.pending[id].map { (id, $0) } })
        let inFlight = try SyncInFlight(batch: transport.prepare(outgoing), sent: sent)
        state.inFlight = inFlight
        save()
        return try await send(inFlight)
    }

    /// Pending changes in batches: in application order (parents first), then by identifier.
    private func pendingBatches() -> [[UUID]] {
        func rank(_ id: UUID) -> Int {
            state.pending[id]?.content.recordType?.applyRank ?? Int.max
        }
        let ids = state.pending.keys.sorted { (rank($0), $0.uuidString) < (rank($1), $1.uuidString) }
        let size = max(transport.maxChangesPerPush, 1)
        let groups = state.isQuotaExceeded
            ? [ids.filter { state.pending[$0]?.content.deleted == true }, ids.filter { state.pending[$0]?.content.deleted != true }]
            : [ids]
        return groups.flatMap { group in
            stride(from: 0, to: group.count, by: size).map { Array(group[$0 ..< min($0 + size, group.count)]) }
        }
    }

    /// Sends `inFlight` and handles each result; the batch is forgotten once answered.
    private func send(_ inFlight: SyncInFlight) async throws -> (winners: [UUID], retries: Bool) {
        let results = try await transport.push(inFlight.batch)
        state.inFlight = nil
        var winners: [UUID] = []
        var retries = false
        for (change, result) in zip(inFlight.batch.changes, results) {
            guard let sent = inFlight.sent[change.id] else {
                continue
            }
            switch handle(result, for: change, sent: sent) {
            case .done: break
            case .remoteWins: winners.append(change.id)
            case .retry: retries = true
            }
        }
        save()
        return (winners, retries)
    }

    private func handle(_ result: SyncPushResult, for change: SyncOutgoingChange, sent: SyncPendingChange) -> Outcome {
        let id = change.id
        // A change made since the batch left stays pending: it leaves in the next batch.
        let isCurrent = state.pending[id] == sent
        switch result {
        case let .applied(version):
            applied(change, version: version, sent: sent, isCurrent: isCurrent)
            return .done
        case .conflict(current: nil):
            // Unknown to the server: sent again as a creation; a deletion has nothing left to delete there.
            state.entries[id]?.version = nil
            guard change.content.deleted else {
                return .retry
            }
            if isCurrent {
                state.pending[id] = nil
                state.entries[id] = nil
            }
            return .done
        case let .conflict(current?):
            return conflict(with: current, for: change, sent: sent, isCurrent: isCurrent)
        case let .rejected(code):
            if code == SyncRejectionCode.quotaExceeded {
                // Nothing is lost: the change stays pending, deletions leave first.
                state.isQuotaExceeded = true
                return .done
            }
            Logger.sync.error("Change refused by the server: \(code, privacy: .public)")
            state.rejected[id] = SyncRejection(code: code, local: sent.local ?? .null)
            if isCurrent {
                state.pending[id] = nil
            }
            return .done
        }
    }

    private func applied(_ change: SyncOutgoingChange, version: Int, sent: SyncPendingChange, isCurrent: Bool) {
        let id = change.id
        accept(change.content, version: version, local: sent.local, for: id)
        if isCurrent {
            state.pending[id] = nil
        }
        // Sent again on top of the other Mac's content: its fields are applied here too (review SY5).
        if remerged.remove(id) != nil {
            state.toApply.insert(id)
        }
        if !change.content.deleted {
            state.isQuotaExceeded = false
        }
        report.sent += 1
    }

    /// Conflict: the server's current content is taken if it is newer (and newer than what this Mac accepted); the
    /// same content as the one sent means the change was already applied (`SYNC.md` § 5, step 1).
    private func conflict(
        with current: SyncRemoteRecord,
        for change: SyncOutgoingChange,
        sent: SyncPendingChange,
        isCurrent: Bool,
    ) -> Outcome {
        let id = change.id
        report.conflicts += 1
        var entry = state.entries[id] ?? SyncEntry(type: change.content.type)
        entry.version = current.version
        guard let content = verified(current) else {
            // Unreadable: never overwritten; this Mac's change is dropped.
            Logger.sync.error("Conflict with an unreadable record: change dropped")
            entry.isUnreadable = true
            state.entries[id] = entry
            if isCurrent {
                state.pending[id] = nil
            }
            return .done
        }
        if content.modifiedAt == change.content.modifiedAt, content.modifiedBy == change.content.modifiedBy {
            state.entries[id] = entry
            accept(change.content, version: current.version, local: sent.local, for: id)
            if isCurrent {
                state.pending[id] = nil
            }
            return .done
        }
        if entry.remote.map(content.isNewer(than:)) ?? true {
            observe(content)
            entry.type = content.type
            entry.remote = content
            entry.isUnreadable = false
        }
        state.entries[id] = entry
        let mine = state.pending[id]?.content ?? change.content
        if content.isNewer(than: mine) || content.isFromNewerVersion {
            state.pending[id] = nil
            return .remoteWins
        }
        remerge(id, onto: content)
        return .retry
    }

    /// Conflict won: the change leaves again on top of the server's content, with only this Mac's changed fields
    /// (review SY5); sent as it was, it would erase what the other Mac changed.
    private func remerge(_ id: UUID, onto current: SyncContent) {
        guard var pending = state.pending[id], let local = pending.local, !pending.content.deleted, !current.deleted,
              current.type == pending.content.type, let type = current.recordType
        else {
            return
        }
        pending.content.fields = SyncFieldMerge.merged(
            remote: current.fields,
            local: local,
            baseline: state.entries[id]?.local,
            knownKeys: type.fieldKeys,
        )
        state.pending[id] = pending
        remerged.insert(id)
    }

    /// `content` is on the server at `version`; `local`: this Mac's fields it carries.
    private func accept(_ content: SyncContent, version: Int, local: SyncJSON?, for id: UUID) {
        var entry = state.entries[id] ?? SyncEntry(type: content.type)
        entry.type = content.type
        entry.version = version
        entry.remote = content
        entry.local = local
        entry.isUnreadable = false
        state.entries[id] = entry
    }
}
