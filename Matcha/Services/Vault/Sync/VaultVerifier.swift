import Foundation

/// Compares what the server shows to this Mac's verified state (`VAULT.md` § 5.2): a root that succeeds is taken with
/// the versions it cites; a root that doesn't is a divergence (§ 5.3); a record that the root in force cites but that
/// the server lost, replaced or deleted is repaired from this Mac. Needs the vault open. Pure type.
nonisolated struct VaultVerifier {
    let keys: VaultCrypto.Keys
    let identifiers: SyncIdentifiers

    enum Outcome: Equatable, Sendable {
        /// No record of the vault, and nothing here: an empty vault.
        case empty
        /// Records of the vault, but no readable root and nothing here: waiting for another Mac.
        case unverifiable
        /// The root in force is still the server's.
        case unchanged
        /// The server's root succeeds the root in force: taken.
        case accepted
        /// The root cites a bucket that neither the server nor this Mac has: the state stays, the next read tries again.
        case incomplete
        /// The server shows an older vault, or one that lost part of it: to reconcile (`VAULT.md` § 5.3).
        case divergent
        /// The root on the server is absent, deleted or doesn't open, and this Mac has one: to repair.
        case tampered
    }

    struct Result: Equatable, Sendable {
        var outcome: Outcome
        /// The state to keep: the new one for `accepted`, the same otherwise.
        var state: VaultState
        /// Cited items without the cited version, here or on the server.
        var waiting: Set<UUID> = []
        /// Records the root in force cites that the server doesn't have as cited, and this Mac does.
        var repairs: Set<UUID> = []
        /// The server's vault, for a divergence.
        var server: VaultServerSide?
    }

    func verify(_ view: VaultServerView, state: VaultState) -> Result {
        let ours = state.root.flatMap { try? VaultManifestCrypto.openRoot($0, vaultID: keys.vaultID, keys: keys) }
        guard let server = VaultServerSide(view, keys: keys) else {
            guard let ours else {
                return Result(outcome: view.hasRecords ? .unverifiable : .empty, state: state)
            }
            var repairs = repairs(of: ours, in: view, state: state)
            repairs.insert(identifiers.vaultManifest(of: keys.vaultID))
            return Result(outcome: .tampered, state: state, repairs: repairs)
        }
        guard let ours else {
            // A new Mac, or a vault never opened here: the server's root, as it is.
            return accept(server, view: view, state: state, ours: nil)
        }
        if state.root == server.rootSealed {
            // The same root: items that were waiting may have arrived, records may have been lost.
            var result = accept(server, view: view, state: state, ours: ours)
            if result.outcome == .accepted {
                result.outcome = .unchanged
            }
            return result
        }
        guard server.root.succeeds(ours), server.root.clock != ours.clock else {
            return Result(outcome: .divergent, state: state, server: server)
        }
        return accept(server, view: view, state: state, ours: ours)
    }

    // MARK: A root that succeeds

    private func accept(_ server: VaultServerSide, view _: VaultServerView, state: VaultState, ours _: VaultRoot?) -> Result {
        var next = state
        var result = Result(outcome: .accepted, state: state)
        next.root = server.rootSealed
        next.clock = server.root.clock
        next.vaultID = keys.vaultID
        // Buckets the server lost: this Mac's, if it has them as cited.
        next.buckets = server.buckets
        for name in server.missingBuckets {
            guard let mine = state.buckets[name], VaultManifestCrypto.bucketDigest(mine) == server.root.buckets[name] else {
                return Result(outcome: .incomplete, state: state)
            }
            next.buckets[name] = mine
            result.repairs.insert(identifiers.vaultBucket(name, of: keys.vaultID))
        }
        let cited = citedItems(of: server, buckets: next.buckets)
        var items: [UUID: VaultHeldItem] = [:]
        for (id, digest) in cited.items {
            switch place(id, digest: digest, server: server, state: state) {
            case let .accept(held): items[id] = held
            case let .keep(held):
                items[id] = held
                result.repairs.insert(id)
            case let .wait(held):
                items[id] = held
                result.waiting.insert(id)
            case .rollback: return Result(outcome: .divergent, state: state, server: server)
            }
        }
        // An item that left the root: deleted if a tombstone says so, otherwise a divergence.
        for (id, held) in state.items where held.isCited && cited.items[id] == nil && cited.tombstones[id] == nil {
            return Result(outcome: .divergent, state: state, server: server)
        }
        next.items = items
        for id in cited.tombstones.keys {
            next.items[id] = nil
        }
        result.state = next
        return result
    }

    private enum Placement {
        /// The server's version, cited.
        case accept(VaultHeldItem)
        /// This Mac's version, cited, that the server lost: kept and repaired.
        case keep(VaultHeldItem)
        /// Neither has the cited version: this Mac's last one stays shown, not cited.
        case wait(VaultHeldItem?)
        /// The cited version is older than this Mac's.
        case rollback
    }

    private func place(_ id: UUID, digest: String, server: VaultServerSide, state: VaultState) -> Placement {
        let mine = state.items[id]
        if let theirs = server.items[id] {
            if let mine, mine.digest != digest, mine.isNewer(than: theirs) {
                return .rollback
            }
            return .accept(theirs)
        }
        if let mine, mine.digest == digest {
            var kept = mine
            kept.isCited = true
            return .keep(kept)
        }
        var shown = mine
        shown?.isCited = false
        return .wait(shown)
    }
}
