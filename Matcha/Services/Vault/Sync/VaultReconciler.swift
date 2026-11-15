import Foundation

/// Merges this Mac's verified state and a divergent server's vault without losing anything (`VAULT.md` § 5.3): the
/// server's state becomes the base, and what this Mac has that it lacks, or has in a newer version, becomes edits to
/// write; the clock of the next root covers both. Pure type.
nonisolated struct VaultReconciler {
    let codec: VaultItemCodec
    let deviceID: UUID

    struct Reconciliation: Sendable {
        /// The state to write on: the server's root and buckets, this Mac's edits for what it adds.
        var state: VaultState
        /// The clock of this Mac's side, to cover in the next root.
        var clock: [String: Int]
        /// How many items this Mac brings back or merges.
        var restored: Int
    }

    func reconcile(_ ours: VaultState, with server: VaultServerSide) throws -> Reconciliation {
        var next = ours
        next.root = server.rootSealed
        next.clock = server.root.clock
        next.buckets = server.buckets
        next.items = server.items
        var restored = 0
        let ourTombstones = tombstones(of: ours)
        let ids = Set(ours.items.filter(\.value.isCited).keys).union(server.cited.keys)
        for id in ids where ours.edits[id] == nil {
            let mine = ours.items[id].flatMap { $0.isCited ? $0 : nil }
            if let edit = try reconcile(id, mine: mine, theirs: server.items[id], server: server, ourTombstone: ourTombstones[id]) {
                next.edits[id] = edit
                restored += 1
            }
        }
        return Reconciliation(state: next, clock: ours.clock, restored: restored)
    }

    /// The edit that brings `id` to the reconciled version; nil when the server's version stands.
    private func reconcile(
        _ id: UUID,
        mine: VaultHeldItem?,
        theirs: VaultHeldItem?,
        server: VaultServerSide,
        ourTombstone: Date?,
    ) throws -> VaultEdit? {
        switch (mine, theirs) {
        case let (mine?, theirs?) where mine.digest != theirs.digest:
            let (ours, others) = try (codec.open(mine.sealed, id: id), codec.open(theirs.sealed, id: id))
            let merged = VaultMerge.reconciled(ours.content, others.content)
            guard merged != others.content else {
                return nil
            }
            let sealed = merged == ours.content ? mine.sealed : try codec.seal(merged, id: id, itemKey: others.itemKey)
            return Self.edit(sealed, content: merged, base: theirs)
        case let (mine?, nil):
            // Only here: kept, unless the server's tombstone is newer than this version.
            if let deletedAt = server.tombstones[id], deletedAt > (mine.modifiedAt ?? .distantPast) {
                return nil
            }
            return VaultEdit(sealed: mine.sealed, modifiedAt: mine.modifiedAt, modifiedBy: mine.modifiedBy, trashedAt: mine.trashedAt)
        case let (nil, theirs?):
            // Only there: kept, unless this Mac's tombstone is newer.
            if let deletedAt = ourTombstone, deletedAt > (theirs.modifiedAt ?? .distantPast) {
                return VaultEdit(sealed: nil, base: theirs.sealed)
            }
            return nil
        default:
            return nil
        }
    }

    private static func edit(_ sealed: VaultSealedItem, content: VaultItemContent, base: VaultHeldItem) -> VaultEdit {
        VaultEdit(
            sealed: sealed,
            base: base.sealed,
            modifiedAt: content.overview.modifiedAt,
            modifiedBy: content.overview.modifiedBy,
            trashedAt: content.overview.trashedAt,
        )
    }

    /// The tombstones of this Mac's buckets.
    private func tombstones(of state: VaultState) -> [UUID: Date] {
        var tombstones: [UUID: Date] = [:]
        for (name, sealed) in state.buckets {
            guard let bucket = try? VaultManifestCrypto.openBucket(sealed, named: name, vaultID: codec.keys.vaultID, keys: codec.keys)
            else {
                continue
            }
            for (text, date) in bucket.deleted {
                if let id = UUID(uuidString: text) {
                    tombstones[id] = date
                }
            }
        }
        return tombstones
    }
}
