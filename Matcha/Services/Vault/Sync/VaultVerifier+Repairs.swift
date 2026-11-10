import Foundation

nonisolated extension VaultVerifier {
    /// What the buckets of a root cite: item → digest, and item → date of its tombstone.
    struct Cited: Equatable, Sendable {
        var items: [UUID: String] = [:]
        var tombstones: [UUID: Date] = [:]
    }

    /// The items and tombstones of `buckets`, which `server`'s root cites (the server's, or this Mac's when the server
    /// lost them).
    func citedItems(of server: VaultServerSide, buckets: [String: Data]) -> Cited {
        var cited = Cited()
        for (name, sealed) in buckets {
            let opened = server.openedBuckets[name] ?? (try? VaultManifestCrypto.openBucket(
                sealed,
                named: name,
                vaultID: keys.vaultID,
                keys: keys,
            ))
            guard let opened else {
                continue
            }
            for (text, digest) in opened.items {
                if let id = UUID(uuidString: text) {
                    cited.items[id] = digest
                }
            }
            for (text, date) in opened.deleted {
                if let id = UUID(uuidString: text) {
                    cited.tombstones[id] = date
                }
            }
        }
        return cited
    }

    /// The records the root in force cites, that the server shows otherwise (missing, deleted, replaced), and that
    /// this Mac holds as cited: its buckets and items (`VAULT.md` § 5.3).
    func repairs(of root: VaultRoot, in view: VaultServerView, state: VaultState) -> Set<UUID> {
        var repairs: Set<UUID> = []
        for (name, digest) in root.buckets {
            let record = view.buckets[name]
            let onServer = record.flatMap { $0.deleted ? nil : $0.manifest }.map(VaultManifestCrypto.bucketDigest)
            if onServer != digest, let mine = state.buckets[name], VaultManifestCrypto.bucketDigest(mine) == digest {
                repairs.insert(identifiers.vaultBucket(name, of: keys.vaultID))
            }
        }
        for (id, held) in state.items where held.isCited {
            let record = view.items[id]
            if record?.deleted != false || record?.item?.digest != held.digest {
                repairs.insert(id)
            }
        }
        return repairs
    }
}
