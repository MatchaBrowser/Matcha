import Foundation

/// The records of the vault as the server shows them, read from the sync state after a complete read (`VAULT.md`
/// § 5.2): the engine keeps them as a type it doesn't apply, and passes them to the vault. Pure type.
nonisolated struct VaultServerView: Equatable, Sendable {
    /// A record of the vault: its server version, its outer content, and the sealed parts its fields carry.
    struct Record: Equatable, Sendable {
        var version: Int?
        var deleted: Bool
        /// Outer date, to write after it (`SYNC.md` § 2.8).
        var modifiedAt: Date?
        /// `manifest` of a root or a bucket; nil if absent or unreadable.
        var manifest: Data?
        /// The three parts of an item; nil if one is absent or unreadable.
        var item: VaultSealedItem?
        /// `fields.vaultId` and `fields.bucket`, as the record names them.
        var vaultID: UUID?
        var bucket: String?
    }

    static let itemType = "vaultItem"
    static let bucketType = "vaultBucket"
    static let rootType = "vaultManifest"
    static let types: Set<String> = [itemType, bucketType, rootType]

    var root: Record?
    var buckets: [String: Record] = [:]
    var items: [UUID: Record] = [:]
    /// Whether the server has any record of the vault, readable or not.
    var hasRecords = false

    /// The records of the vault `vaultID` in `state`. A root or a bucket whose identifier isn't the one derived from
    /// its fields is ignored (`SYNC.md` § 2.2); so is a record of another vault.
    static func read(from state: SyncState, vaultID: UUID, identifiers: SyncIdentifiers) -> VaultServerView {
        var view = VaultServerView()
        for (id, entry) in state.entries where types.contains(entry.type) {
            view.hasRecords = true
            guard let content = entry.remote else {
                continue
            }
            let record = Self.record(content, version: entry.version)
            view.place(record, id: id, type: entry.type, vaultID: vaultID, identifiers: identifiers)
        }
        return view
    }

    private mutating func place(_ record: Record, id: UUID, type: String, vaultID: UUID, identifiers: SyncIdentifiers) {
        switch type {
        case Self.rootType where id == identifiers.vaultManifest(of: vaultID):
            // A deletion has no fields: it is the root's, by its identifier.
            if record.deleted || record.vaultID == vaultID {
                root = record
            }
        case Self.bucketType:
            let name = VaultBucket.names.first { identifiers.vaultBucket($0, of: vaultID) == id }
            if let name, record.deleted || (record.vaultID == vaultID && record.bucket == name) {
                buckets[name] = record
            }
        case Self.itemType where record.deleted || record.vaultID == vaultID:
            items[id] = record
        default:
            break
        }
    }

    private static func record(_ content: SyncContent, version: Int?) -> Record {
        let fields = VaultEntry(content.fields.objectValue)
        var record = Record(version: version, deleted: content.deleted, modifiedAt: content.modifiedAt)
        guard !content.deleted, fields.integer("keyVersion") == VaultCrypto.keyVersion else {
            return record
        }
        record.vaultID = UUID(uuidString: fields.string("vaultId"))
        record.bucket = fields.string("bucket").isEmpty ? nil : fields.string("bucket")
        record.manifest = Data(base64Encoded: fields.string("manifest"))
        let parts = ["itemKey", "overview", "details"].compactMap { Data(base64Encoded: fields.string($0)) }
        if parts.count == 3 {
            record.item = VaultSealedItem(itemKey: parts[0], overview: parts[1], details: parts[2])
        }
        return record
    }
}
