import Foundation

/// Sends a batch of the vault and reads its answer strictly (`VAULT.md` § 5.1): one result per change, by
/// identifier; an atomic batch is either all applied or not applied at all, anything else is unreadable.
nonisolated enum VaultPusher {
    enum Outcome: Equatable, Sendable {
        /// Every change applied: the new server versions.
        case applied([UUID: Int])
        /// Nothing written (atomic): to read, merge and compose again. A staging or repair batch may be partly applied:
        /// `applied` has those versions.
        case conflict(applied: [UUID: Int])
        /// The account is full: nothing lost, the batch waits.
        case quotaExceeded
        /// A change refused for itself (`payload_too_large`, `invalid_payload`): those items stay here.
        case rejected([UUID])
    }

    /// The body of the push: the changes, atomic for an atomic batch.
    static func body(of batch: VaultBatch) throws -> Data {
        try SyncCoding.encoder().encode(SyncPushRequest(atomic: batch.kind == .atomic ? true : nil, changes: batch.changes))
    }

    @MainActor
    static func send(_ batch: VaultBatch, with account: SyncVaultAccount) async throws -> Outcome {
        let response = try await account.push(body(of: batch), batch.key)
        return try outcome(of: response.results, for: batch)
    }

    /// The outcome of the results of `batch`; throws `unreadableAnswer` for an answer that doesn't match it.
    static func outcome(of results: [SyncServerPushResult], for batch: VaultBatch) throws -> Outcome {
        let byID = try matched(results, to: batch)
        var tally = Tally()
        for change in batch.changes {
            if let result = byID[change.id] {
                try tally.count(result, id: change.id, atomic: batch.kind == .atomic)
            }
        }
        if batch.kind == .atomic, !tally.applied.isEmpty, tally.applied.count != batch.changes.count {
            throw SyncClientError.unreadableAnswer
        }
        if tally.applied.count == batch.changes.count {
            return .applied(tally.applied)
        }
        if tally.quota {
            return .quotaExceeded
        }
        return tally.rejected.isEmpty ? .conflict(applied: tally.applied) : .rejected(tally.rejected)
    }

    /// One result per change, by identifier, its `current` for that identifier only (`SYNC.md` § 4.6).
    private static func matched(_ results: [SyncServerPushResult], to batch: VaultBatch) throws -> [UUID: SyncServerPushResult] {
        var byID: [UUID: SyncServerPushResult] = [:]
        for result in results {
            guard let id = result.id, byID[id] == nil, result.current.map({ $0.id == id }) ?? true else {
                throw SyncClientError.unreadableAnswer
            }
            byID[id] = result
        }
        guard byID.count == batch.changes.count, batch.changes.allSatisfy({ byID[$0.id] != nil }) else {
            throw SyncClientError.unreadableAnswer
        }
        return byID
    }

    private struct Tally {
        var applied: [UUID: Int] = [:]
        var rejected: [UUID] = []
        var quota = false

        mutating func count(_ result: SyncServerPushResult, id: UUID, atomic: Bool) throws {
            switch result.status {
            case "applied":
                guard let version = result.version else {
                    throw SyncClientError.unreadableAnswer
                }
                applied[id] = version
            case "rejected" where result.code == SyncServerError.quotaExceeded: quota = true
            case "rejected": rejected.append(id)
            case "conflict": break
            case "aborted" where atomic: break
            default: throw SyncClientError.unreadableAnswer
            }
        }
    }
}
