import Foundation

/// The vault as the server shows it, verified under the server's own root (`VAULT.md` § 5.2): its root, the cited
/// buckets whose record has the cited digest, and the cited items whose record has the cited digest. Pure type.
nonisolated struct VaultServerSide: Equatable, Sendable {
    var root: VaultRoot
    var rootSealed: Data
    /// The cited buckets found with their cited digest, sealed and opened.
    var buckets: [String: Data] = [:]
    var openedBuckets: [String: VaultBucket] = [:]
    /// The cited buckets not found with their digest.
    var missingBuckets: Set<String> = []
    /// The cited items found with their cited digest, their overview opened.
    var items: [UUID: VaultHeldItem] = [:]
    /// Item → cited digest, from the buckets found.
    var cited: [UUID: String] = [:]
    /// Item → date of its tombstone, from the buckets found.
    var tombstones: [UUID: Date] = [:]

    /// Reads the server's vault under its root; nil if the root is absent, deleted or doesn't open.
    init?(_ view: VaultServerView, keys: VaultCrypto.Keys) {
        guard let record = view.root, !record.deleted, let sealed = record.manifest,
              let root = try? VaultManifestCrypto.openRoot(sealed, vaultID: keys.vaultID, keys: keys)
        else {
            return nil
        }
        self.root = root
        rootSealed = sealed
        for (name, digest) in root.buckets {
            guard let bucketSealed = view.buckets[name]?.manifest, !(view.buckets[name]?.deleted ?? true),
                  VaultManifestCrypto.bucketDigest(bucketSealed) == digest,
                  let bucket = try? VaultManifestCrypto.openBucket(bucketSealed, named: name, vaultID: keys.vaultID, keys: keys)
            else {
                missingBuckets.insert(name)
                continue
            }
            buckets[name] = bucketSealed
            openedBuckets[name] = bucket
            read(bucket)
        }
        for (id, digest) in cited {
            if let item = view.items[id]?.item, item.digest == digest, let held = Self.held(item, id: id, keys: keys) {
                items[id] = held
            }
        }
    }

    private mutating func read(_ bucket: VaultBucket) {
        for (text, digest) in bucket.items {
            if let id = UUID(uuidString: text) {
                cited[id] = digest
            }
        }
        for (text, date) in bucket.deleted {
            if let id = UUID(uuidString: text) {
                tombstones[id] = date
            }
        }
    }

    /// A version of an item, its overview opened for its dates; nil if it doesn't open.
    static func held(_ item: VaultSealedItem, id: UUID, keys: VaultCrypto.Keys) -> VaultHeldItem? {
        let address = VaultCrypto.Address(vaultID: keys.vaultID, itemID: id)
        guard let itemKey = try? VaultCrypto.openItemKey(of: item, at: address, keys: keys),
              let data = try? VaultCrypto.openOverview(of: item, itemKey: itemKey, at: address),
              let json = try? SyncCoding.decoder().decode(SyncJSON.self, from: data)
        else {
            return nil
        }
        let overview = VaultOverview(json: json)
        return VaultHeldItem(sealed: item, modifiedAt: overview.modifiedAt, modifiedBy: overview.modifiedBy, trashedAt: overview.trashedAt)
    }
}

nonisolated extension VaultHeldItem {
    /// Whether this version is more recent than `other`, by the dates of their overviews (`VAULT.md` § 5.2).
    func isNewer(than other: VaultHeldItem) -> Bool {
        VaultOverview(modifiedAt: modifiedAt, modifiedBy: modifiedBy)
            .isNewer(than: VaultOverview(modifiedAt: other.modifiedAt, modifiedBy: other.modifiedBy))
    }
}
