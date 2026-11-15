import Foundation

/// The secrets of an item (`VAULT.md` § 9.2): opened only when they are used, forgotten afterwards. Unknown keys are
/// kept and written back.
nonisolated struct VaultDetails: Equatable, Hashable, Sendable {
    /// Credentials of CXF types (`VaultCredentialType`): `id`, `type`, and the values of the type.
    var credentials: [VaultEntry] = []
    /// Custom fields: `id`, `label`, `type` (`VaultFieldType`), `value`.
    var fields: [VaultEntry] = []
    var notes = ""
    /// Files of the item (`VAULT.md` § 6): `id`, `name`, `type`, `size`, `sha256`, `key`, `chunks`, `createdAt`.
    var files: [VaultEntry] = []
    var history: [VaultHistoryEntry] = []
    var createdAt: Date?
    var extra: [String: SyncJSON] = [:]

    static let knownKeys: Set<String> = ["credentials", "fields", "notes", "files", "history", "createdAt"]
    /// 64 KiB of notes, 96 KiB of details before padding (`VAULT.md` § 3.2, § 9.2).
    static let maximumNotesBytes = 64 * 1024
    static let maximumBytes = 96 * 1024

    /// The first credential of `type`.
    func credential(_ type: String) -> VaultEntry? {
        credentials.first { $0.string("type") == type }
    }

    /// Changes the first credential of `type`, created if needed.
    mutating func updateCredential(_ type: String, _ change: (inout VaultEntry) -> Void) {
        if let index = credentials.firstIndex(where: { $0.string("type") == type }) {
            change(&credentials[index])
        } else {
            var entry = VaultEntry(["type": .string(type)])
            entry.id = VaultEntryID.make()
            change(&entry)
            credentials.append(entry)
        }
    }
}

/// An old value of a secret (`VAULT.md` § 9.5).
nonisolated struct VaultHistoryEntry: Codable, Equatable, Hashable, Sendable {
    /// The secret: `<credential id>.<key>`, `fields.<field id>` or `notes`.
    var field: String
    var value: String
    /// Date and Mac of the value replaced (`at` and `by` in the JSON).
    var date: Date
    var device: UUID?

    enum CodingKeys: String, CodingKey {
        case field
        case value
        case date = "at"
        case device = "by"
    }
}

// MARK: JSON

nonisolated extension VaultDetails {
    init(json: SyncJSON) {
        let object = json.objectValue
        credentials = Self.entries(object["credentials"])
        fields = Self.entries(object["fields"])
        if case let .string(text)? = object["notes"] {
            notes = text
        }
        files = Self.entries(object["files"])
        if case let .array(values)? = object["history"] {
            history = values.compactMap { try? $0.decoded(as: VaultHistoryEntry.self) }
        }
        if case let .string(text)? = object["createdAt"] {
            createdAt = SyncCoding.date(from: text)
        }
        extra = object.filter { !Self.knownKeys.contains($0.key) }
    }

    var json: SyncJSON {
        var object = extra
        object["credentials"] = .array(credentials.map { .object($0.values) })
        object["fields"] = .array(fields.map { .object($0.values) })
        object["notes"] = .string(notes)
        object["files"] = .array(files.map { .object($0.values) })
        object["history"] = .array(history.compactMap { try? SyncJSON.encoding($0) })
        object["createdAt"] = createdAt.map { .string(SyncCoding.string(from: $0)) } ?? .null
        return .object(object)
    }

    private static func entries(_ json: SyncJSON?) -> [VaultEntry] {
        guard case let .array(values)? = json else {
            return []
        }
        return values.compactMap {
            if case let .object(object) = $0 {
                return VaultEntry(object)
            }
            return nil
        }
    }
}
