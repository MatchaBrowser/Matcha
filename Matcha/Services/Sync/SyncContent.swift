import Foundation

/// Contenu d'un enregistrement synchronisé (tâche 7.4, `SYNC.md` § 2.2) : objet JSON en UTF-8, chiffré par le transport
/// d'un serveur. `type` reste du texte : un type inconnu (venu d'une version plus récente) est gardé tel quel. Type pur.
nonisolated struct SyncContent: Codable, Equatable, Sendable {
    var type: String
    var schema: Int
    /// Horloge hybride (`SyncClock`), à la milliseconde.
    var modifiedAt: Date
    /// Appareil qui a écrit ce contenu.
    var modifiedBy: UUID
    var deleted: Bool
    /// Champs du type ; objet vide pour une suppression.
    var fields: SyncJSON

    init(type: String, schema: Int, modifiedAt: Date, modifiedBy: UUID, deleted: Bool, fields: SyncJSON) {
        self.type = type
        self.schema = schema
        self.modifiedAt = SyncCoding.rounded(modifiedAt)
        self.modifiedBy = modifiedBy
        self.deleted = deleted
        self.fields = deleted ? .emptyObject : fields
    }

    /// Modification de `fields`, au format actuel de leur type.
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

    /// Suppression d'un enregistrement de type `type`.
    static func deletion(of type: String, schema: Int, modifiedAt: Date, modifiedBy: UUID) -> SyncContent {
        SyncContent(type: type, schema: schema, modifiedAt: modifiedAt, modifiedBy: modifiedBy, deleted: true, fields: .emptyObject)
    }

    var recordType: SyncRecordType? {
        SyncRecordType(rawValue: type)
    }

    /// Écrit avec un format plus récent que celui que connaît ce Matcha : gardé tel quel, jamais modifié.
    var isFromNewerVersion: Bool {
        guard let recordType else {
            return true
        }
        return schema > recordType.schema
    }

    /// Champs lus et vérifiés ; nil pour une suppression, un type ou un format inconnu, ou une valeur illisible
    /// (`SYNC.md` § 2.3 : l'enregistrement est alors ignoré, sans être écrasé ni supprimé).
    var readableFields: SyncFields? {
        guard !deleted, !isFromNewerVersion, let recordType else {
            return nil
        }
        return SyncFields(json: fields, type: recordType)
    }

    /// Règle des conflits (`SYNC.md` § 2.3) : le plus récent `modifiedAt` gagne ; à égalité, le plus grand `modifiedBy`
    /// (UUID en minuscules, comparés caractère par caractère).
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
