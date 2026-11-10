import Foundation
import OSLog

/// Sending the vault's writes (`VAULT.md` § 5.1, § 5.3): the batch left without an answer first, as it is; then the
/// edits of this Mac; then the repairs.
extension VaultService {
    /// A clock more than 24 h ahead sends nothing (`SYNC.md` § 2.8).
    static let maximumClockLead: TimeInterval = 24 * 3600

    func composer(for account: SyncVaultAccount, session: VaultSession) -> VaultComposer {
        VaultComposer(
            keys: session.keys,
            identifiers: account.identifiers,
            dataKey: account.dataKey,
            deviceID: account.deviceID,
            now: now(),
        )
    }

    /// Writes the edits of this Mac (and, for a reconciliation, a root that covers `clock`).
    func write(view: VaultServerView, clock: [String: Int] = [:]) async {
        guard let session, let account, clockLead() < Self.maximumClockLead else {
            return
        }
        if let inFlight = state.inFlight {
            guard await send(inFlight, with: account) else {
                return
            }
        }
        let batches: [VaultBatch]
        do {
            batches = try composer(for: account, session: session).batches(for: state, view: view, clock: clock)
        } catch {
            Logger.vault.error("Vault batch not composed: \(error.logSummary, privacy: .public)")
            return
        }
        for batch in batches {
            state.inFlight = batch
            saveState()
            guard await send(batch, with: account) else {
                return
            }
        }
    }

    /// Sends a batch; true if it was applied (the next one may follow).
    private func send(_ batch: VaultBatch, with account: SyncVaultAccount) async -> Bool {
        let outcome: VaultPusher.Outcome
        do {
            outcome = try await VaultPusher.send(batch, with: account)
        } catch {
            // No answer, or an unreadable one: the batch stays in flight, sent again as it is (`SYNC.md` § 4.6).
            Logger.vault.error("Vault batch not answered: \(error.logSummary, privacy: .public)")
            return false
        }
        state.inFlight = nil
        defer {
            saveState()
            rebuildItems()
        }
        switch outcome {
        case let .applied(versions):
            state.versions.merge(versions) { _, new in new }
            applied(batch)
            setWriteError(nil)
            return true
        case let .conflict(versions):
            state.versions.merge(versions) { _, new in new }
            // Read, verify, merge, then compose again (`VAULT.md` § 5.1).
            account.requestCycle()
        case .quotaExceeded:
            setWriteError(SyncServerError(status: 507, code: SyncServerError.quotaExceeded))
        case let .rejected(ids):
            for id in ids {
                state.edits[id] = nil
            }
            setWriteError(VaultError.itemTooLarge)
            account.requestCycle()
        }
        return false
    }

    /// An applied batch becomes the state in force: its root, its buckets and its items; the edits it wrote are done,
    /// unless changed again meanwhile.
    private func applied(_ batch: VaultBatch) {
        switch batch.kind {
        case .atomic:
            state.root = batch.root
            state.clock = batch.clock
            state.buckets = batch.buckets
            for (id, held) in batch.items {
                state.items[id] = held
                if state.edits[id]?.sealed == held.sealed {
                    state.edits[id] = nil
                }
            }
            for id in batch.deletions {
                state.items[id] = nil
                if state.edits[id]?.sealed == nil {
                    state.edits[id] = nil
                }
            }
        case .staging, .repair:
            break
        }
    }

    // MARK: Repairs

    /// Sends back, as this Mac holds them, the records the server lost or replaced (`VAULT.md` § 5.3); at most once a
    /// day each.
    func repair(_ ids: Set<UUID>, view: VaultServerView) async {
        guard let session, let account, clockLead() < Self.maximumClockLead else {
            return
        }
        let due = ids.filter { state.repairs[$0].map { now().timeIntervalSince($0) > 24 * 3600 } ?? true }
        guard !due.isEmpty else {
            return
        }
        do {
            let batch = try composer(for: account, session: session).repairBatch(due, state: state, view: view)
            for id in due {
                state.repairs[id] = now()
            }
            Logger.vault.notice("Vault repair: \(due.count, privacy: .public) records sent back")
            _ = await send(batch, with: account)
        } catch {
            Logger.vault.error("Vault repair not composed: \(error.logSummary, privacy: .public)")
        }
    }
}
