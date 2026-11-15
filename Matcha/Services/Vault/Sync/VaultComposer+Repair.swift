import Foundation

nonisolated extension VaultComposer {
    /// The records to send back as this Mac holds them (`VAULT.md` § 5.3): the root, buckets and items of the state
    /// in force named by `ids`. Only the outer layer is new; the inner layer, hence every digest, stays the same.
    func repairBatch(_ ids: Set<UUID>, state: VaultState, view: VaultServerView) throws -> VaultBatch {
        var batch = VaultBatch(kind: .repair, key: UUID(), changes: [])
        let rootID = identifiers.vaultManifest(of: keys.vaultID)
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            let bucketName = VaultBucket.names.first { identifiers.vaultBucket($0, of: keys.vaultID) == id }
            if id == rootID, let root = state.root {
                let fields: [String: SyncJSON] = ["manifest": .string(root.base64EncodedString())]
                try batch.changes.append(change(id, type: VaultServerView.rootType, fields: fields, state: state, view: view.root))
            } else if let name = bucketName, let sealed = state.buckets[name] {
                let fields: [String: SyncJSON] = ["bucket": .string(name), "manifest": .string(sealed.base64EncodedString())]
                try batch.changes.append(change(
                    id,
                    type: VaultServerView.bucketType,
                    fields: fields,
                    state: state,
                    view: view.buckets[name],
                ))
            } else if let held = state.items[id], held.isCited {
                try batch.changes.append(change(
                    id,
                    type: VaultServerView.itemType,
                    fields: Self.fields(of: held.sealed),
                    state: state,
                    view: view.items[id],
                ))
            }
        }
        return batch
    }
}
