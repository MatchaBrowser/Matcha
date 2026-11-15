import CryptoKit
import Foundation

/// Builds the batches of a write of the vault (`VAULT.md` § 5.1): the items changed on this Mac, their buckets and a
/// root whose clock adds one write of this Mac, each record encrypted as a sync record (`SYNC.md` § 3.5) on top of the
/// version the server has. Pure type.
nonisolated struct VaultComposer {
    let keys: VaultCrypto.Keys
    let identifiers: SyncIdentifiers
    let dataKey: SymmetricKey
    let deviceID: UUID
    var now: Date

    /// Beyond 100 items, the items go first in ordinary batches, not cited, then an atomic batch with the buckets and the
    /// root (`VAULT.md` § 5.1).
    static let largeWrite = 100
    static let stagingBatchSize = 200

    /// The batches that write the edits of `state` on top of its root in force; `clock` is a clock to add (that of
    /// the other side of a reconciliation). Empty without any edit.
    func batches(for state: VaultState, view: VaultServerView, clock extra: [String: Int] = [:]) throws -> [VaultBatch] {
        guard !state.edits.isEmpty || !extra.isEmpty else {
            return []
        }
        var root = try state.root.map { try VaultManifestCrypto.openRoot($0, vaultID: keys.vaultID, keys: keys) } ?? VaultRoot()
        var atomic = VaultBatch(kind: .atomic, key: UUID(), changes: [])
        atomic.buckets = state.buckets
        let touched = Set(state.edits.keys.map(VaultBucket.name))
        for name in touched.sorted() {
            var bucket = try state.buckets[name].map {
                try VaultManifestCrypto.openBucket($0, named: name, vaultID: keys.vaultID, keys: keys)
            } ?? VaultBucket()
            apply(state.edits.filter { VaultBucket.name(of: $0.key) == name }, to: &bucket, batch: &atomic)
            let sealed = try VaultManifestCrypto.sealBucket(bucket, named: name, vaultID: keys.vaultID, keys: keys)
            atomic.buckets[name] = sealed
            root.buckets[name] = bucket.isEmpty ? nil : VaultManifestCrypto.bucketDigest(sealed)
            let id = identifiers.vaultBucket(name, of: keys.vaultID)
            let fields: [String: SyncJSON] = ["bucket": .string(name), "manifest": .string(sealed.base64EncodedString())]
            try atomic.changes.append(change(id, type: VaultServerView.bucketType, fields: fields, state: state, view: view.buckets[name]))
        }
        root.clock = VaultRoot(clock: root.mergedClock(with: VaultRoot(clock: extra))).clock(ofWriteBy: deviceID)
        root.modifiedAt = later(than: root.modifiedAt)
        root.modifiedBy = deviceID
        let sealedRoot = try VaultManifestCrypto.sealRoot(root, vaultID: keys.vaultID, keys: keys)
        (atomic.root, atomic.clock) = (sealedRoot, root.clock)
        let rootID = identifiers.vaultManifest(of: keys.vaultID)
        try atomic.changes.append(change(
            rootID,
            type: VaultServerView.rootType,
            fields: ["manifest": .string(sealedRoot.base64EncodedString())],
            state: state,
            view: view.root,
        ))
        let items = try state.edits.keys.sorted { $0.uuidString < $1.uuidString }.map { try itemChange($0, state: state, view: view) }
        guard items.count > Self.largeWrite else {
            atomic.changes.insert(contentsOf: items, at: 0)
            return [atomic]
        }
        let staging = stride(from: 0, to: items.count, by: Self.stagingBatchSize).map {
            VaultBatch(kind: .staging, key: UUID(), changes: Array(items[$0 ..< min($0 + Self.stagingBatchSize, items.count)]))
        }
        return staging + [atomic]
    }

    /// The edits of a bucket: a new version cited by its digest, a deletion by a tombstone; tombstones older than 180
    /// days go.
    private func apply(_ edits: [UUID: VaultEdit], to bucket: inout VaultBucket, batch: inout VaultBatch) {
        for (id, edit) in edits {
            let key = id.uuidString.lowercased()
            if let sealed = edit.sealed {
                bucket.items[key] = sealed.digest
                bucket.deleted[key] = nil
                batch.items[id] = VaultHeldItem(
                    sealed: sealed,
                    modifiedAt: edit.modifiedAt,
                    modifiedBy: edit.modifiedBy,
                    trashedAt: edit.trashedAt,
                )
            } else {
                bucket.items[key] = nil
                bucket.deleted[key] = now
                batch.deletions.insert(id)
            }
        }
        bucket.deleted = bucket.deleted.filter { now.timeIntervalSince($0.value) < VaultBucket.tombstoneLifetime }
    }

    /// The change of an item: its new version, or its deletion for good.
    func itemChange(_ id: UUID, state: VaultState, view: VaultServerView) throws -> SyncServerChange {
        guard let sealed = state.edits[id]?.sealed ?? (state.edits[id] == nil ? state.items[id]?.sealed : nil) else {
            return try change(id, type: VaultServerView.itemType, fields: nil, state: state, view: view.items[id])
        }
        return try change(id, type: VaultServerView.itemType, fields: Self.fields(of: sealed), state: state, view: view.items[id])
    }

    static func fields(of item: VaultSealedItem) -> [String: SyncJSON] {
        [
            "itemKey": .string(item.itemKey.base64EncodedString()),
            "overview": .string(item.overview.base64EncodedString()),
            "details": .string(item.details.base64EncodedString()),
        ]
    }

    /// A record of the vault, encrypted with the data key, after the version the server has; nil fields: a deletion.
    func change(
        _ id: UUID,
        type: String,
        fields: [String: SyncJSON]?,
        state: VaultState,
        view: VaultServerView.Record?,
    ) throws -> SyncServerChange {
        var all = fields ?? [:]
        all["vaultId"] = .string(keys.vaultID.uuidString)
        all["keyVersion"] = .number(Double(VaultCrypto.keyVersion))
        let modifiedAt = later(than: view?.modifiedAt)
        let content = fields == nil
            ? SyncContent.deletion(of: type, schema: 1, modifiedAt: modifiedAt, modifiedBy: deviceID)
            : SyncContent(type: type, schema: 1, modifiedAt: modifiedAt, modifiedBy: deviceID, deleted: false, fields: .object(all))
        let payload = try SyncCrypto.encryptRecord(SyncCoding.encoder().encode(content), id: id, keyVersion: 1, dataKey: dataKey)
        return SyncServerChange(
            id: id,
            baseVersion: state.baseVersion(of: id, engine: view?.version),
            deleted: content.deleted,
            keyVersion: 1,
            payload: payload,
        )
    }

    /// Now, or 1 ms after `date` if it is ahead: a write always comes after what it replaces (`SYNC.md` § 2.8).
    func later(than date: Date?) -> Date {
        guard let date, date >= now else {
            return now
        }
        return date.addingTimeInterval(0.001)
    }
}
