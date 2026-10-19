import Foundation

/// Content of a synced record (task 7.4, `SYNC.md` § 2.2): a JSON object in UTF-8, encrypted by a server's
/// transport. `type` stays text: an unknown type (from a newer version) is kept as is. Pure type.
nonisolated struct SyncContent: Codable, Equatable, Sendable {
    var type: String
    var schema: Int
    /// Hybrid clock (`SyncClock`), to the millisecond.
    var modifiedAt: Date
    /// Device that wrote this content.
    var modifiedBy: UUID
    var deleted: Bool
    /// Fields of the type; empty object for a deletion.
    var fields: SyncJSON

    init(type: String, schema: Int, modifiedAt: Date, modifiedBy: UUID, deleted: Bool, fields: SyncJSON) {
        self.type = type
        self.schema = schema
        self.modifiedAt = SyncCoding.rounded(modifiedAt)
        self.modifiedBy = modifiedBy
        self.deleted = deleted
        self.fields = deleted ? .emptyObject : fields
    }

    /// Modification of `fields`, in the current format of their type.
    init(fields: SyncFields, modifiedAt: Date, modifiedBy: UUID) {
        self.init(
            type: fields.type.rawValue,
            schema: fields.type.schema,
            modifiedAt: modifiedAt,
            modifiedBy: modifiedBy,
            deleted: false,
            fields: fields.json,
        )
    }

    /// Deletion of a record of type `type`.
    static func deletion(of type: String, schema: Int, modifiedAt: Date, modifiedBy: UUID) -> SyncContent {
        SyncContent(type: type, schema: schema, modifiedAt: modifiedAt, modifiedBy: modifiedBy, deleted: true, fields: .emptyObject)
    }

    var recordType: SyncRecordType? {
        SyncRecordType(rawValue: type)
    }

    /// Written with a newer format than the one this Matcha knows: kept as is, never modified.
    var isFromNewerVersion: Bool {
        guard let recordType else {
            return true
        }
        return schema > recordType.schema
    }

    /// Fields read and checked; nil for a deletion, an unknown type or format, or an unreadable value
    /// (`SYNC.md` § 2.3: the record is then ignored, without being overwritten or deleted).
    var readableFields: SyncFields? {
        guard !deleted, !isFromNewerVersion, let recordType else {
            return nil
        }
        return SyncFields(json: fields, type: recordType)
    }

    /// Conflict rule (`SYNC.md` § 2.3): the most recent `modifiedAt` wins; on a tie, the greatest `modifiedBy`
    /// (lowercase UUIDs, compared character by character).
    func isNewer(than other: SyncContent) -> Bool {
        let mine = SyncCoding.milliseconds(of: modifiedAt)
        let theirs = SyncCoding.milliseconds(of: other.modifiedAt)
        if mine != theirs {
            return mine > theirs
        }
        return modifiedBy.uuidString.lowercased() > other.modifiedBy.uuidString.lowercased()
    }

    func encoded() throws -> Data {
        try SyncCoding.encoder().encode(self)
    }

    static func decoded(from data: Data) throws -> SyncContent {
        try SyncCoding.decoder().decode(SyncContent.self, from: data)
    }
}
