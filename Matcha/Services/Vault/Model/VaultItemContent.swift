import Foundation

/// The inner layer of an item, opened: its overview and its details (`VAULT.md` § 3.2). The rules on its secrets
/// (history, `VAULT.md` § 9.5) are here. Pure type.
nonisolated struct VaultItemContent: Equatable, Hashable, Sendable {
    var overview = VaultOverview()
    var details = VaultDetails()

    /// At most 10 old values per secret, 50 in all (`VAULT.md` § 9.5).
    static let historyPerSecret = 10
    static let historyTotal = 50

    /// Each secret of the details, by its path in the history: `<credential id>.<key>`, `fields.<field id>`, `notes`.
    var secrets: [String: String] {
        var secrets: [String: String] = [:]
        for credential in details.credentials {
            for key in VaultCredentialType.secretKeys(of: credential.string("type")) where !credential.string(key).isEmpty {
                secrets["\(credential.id).\(key)"] = credential.string(key)
            }
        }
        for field in details.fields where VaultFieldType(rawValue: field.string("type"))?.isSecret == true {
            if !field.string("value").isEmpty {
                secrets["fields.\(field.id)"] = field.string("value")
            }
        }
        if !details.notes.isEmpty {
            secrets["notes"] = details.notes
        }
        return secrets
    }

    /// Writes the secrets of `older` that this version replaced or removed into the history, dated by `older`.
    mutating func keepHistory(of older: VaultItemContent) {
        let mine = secrets
        let date = older.overview.modifiedAt ?? older.details.createdAt ?? .now
        for (path, value) in older.secrets where mine[path] != value {
            addHistory(VaultHistoryEntry(field: path, value: value, date: date, device: older.overview.modifiedBy))
        }
    }

    /// Adds an old value, unless the same secret already has it.
    mutating func addHistory(_ entry: VaultHistoryEntry) {
        guard !details.history.contains(where: { $0.field == entry.field && $0.value == entry.value }) else {
            return
        }
        details.history.append(entry)
        trimHistory()
    }

    /// Newest first, at most 10 per secret and 50 in all; then the oldest go until the details fit their limit.
    mutating func trimHistory() {
        var counts: [String: Int] = [:]
        details.history = details.history
            .sorted { $0.date > $1.date }
            .filter { entry in
                counts[entry.field, default: 0] += 1
                return counts[entry.field, default: 0] <= Self.historyPerSecret
            }
        if details.history.count > Self.historyTotal {
            details.history.removeLast(details.history.count - Self.historyTotal)
        }
        while !details.history.isEmpty, (try? encodedDetails().count) ?? 0 > VaultDetails.maximumBytes {
            details.history.removeLast()
        }
    }

    func encodedOverview() throws -> Data {
        try SyncCoding.encoder().encode(overview.json)
    }

    func encodedDetails() throws -> Data {
        try SyncCoding.encoder().encode(details.json)
    }

    /// Opened from the two decrypted parts.
    init(overview: Data, details: Data) throws {
        self.overview = try VaultOverview(json: SyncCoding.decoder().decode(SyncJSON.self, from: overview))
        self.details = try VaultDetails(json: SyncCoding.decoder().decode(SyncJSON.self, from: details))
    }

    init(overview: VaultOverview = VaultOverview(), details: VaultDetails = VaultDetails()) {
        self.overview = overview
        self.details = details
    }

    /// Whether this version can be changed here: a known category, and only known credential types.
    var isEditable: Bool {
        overview.category.isKnown && details.credentials.allSatisfy { VaultCredentialType.known.contains($0.string("type")) }
    }
}
