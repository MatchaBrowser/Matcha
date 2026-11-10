import Foundation

/// What the list and the search of the vault read (`VAULT.md` § 9.1): opened with the vault, never a secret. Unknown
/// keys are kept and written back.
nonisolated struct VaultOverview: Equatable, Hashable, Sendable {
    var category: VaultCategory = .custom
    var title = ""
    /// Shown under the title: user name, last digits of a card, fingerprint of a key; never a secret.
    var subtitle = ""
    var favorite = false
    var tags: [String] = []
    /// The addresses of a login, as typed (`VAULT.md` § 8.2), and how a page must match them.
    var urls: [String] = []
    var match = VaultURLMatch.site
    /// When the item went to the trash; nil out of it.
    var trashedAt: Date?
    /// Last change of the content (sync clock) and its Mac: authenticated, they settle conflicts (`VAULT.md` § 5.4).
    var modifiedAt: Date?
    var modifiedBy: UUID?
    /// Keys of a newer version, kept as they came.
    var extra: [String: SyncJSON] = [:]

    static let knownKeys: Set<String> = [
        "category", "title", "subtitle", "favorite", "tags", "urls", "match", "trashedAt", "modifiedAt", "modifiedBy",
    ]

    var isTrashed: Bool {
        trashedAt != nil
    }

    /// Whether this version is more recent than `other`: `modifiedAt` to the millisecond, then `modifiedBy` in
    /// lowercase (`SYNC.md` § 2.3).
    func isNewer(than other: VaultOverview) -> Bool {
        let mine = modifiedAt.map(SyncCoding.milliseconds) ?? .min
        let theirs = other.modifiedAt.map(SyncCoding.milliseconds) ?? .min
        if mine != theirs {
            return mine > theirs
        }
        return (modifiedBy?.uuidString.lowercased() ?? "") > (other.modifiedBy?.uuidString.lowercased() ?? "")
    }
}

// MARK: JSON

nonisolated extension VaultOverview {
    /// Read from the opened JSON; a value of the wrong type takes its default (`VAULT.md` § 9.3).
    init(json: SyncJSON) {
        let object = json.objectValue
        let entry = VaultEntry(object)
        category = VaultCategory(rawValue: entry.string("category").isEmpty ? "custom" : entry.string("category"))
        title = entry.string("title")
        subtitle = entry.string("subtitle")
        if case let .bool(value)? = object["favorite"] {
            favorite = value
        }
        tags = Self.strings(object["tags"])
        urls = Self.strings(object["urls"])
        // A rule of a newer version: the strictest one meanwhile.
        match = entry.string("match").isEmpty ? .site : VaultURLMatch(rawValue: entry.string("match")) ?? .page
        trashedAt = SyncCoding.date(from: entry.string("trashedAt"))
        modifiedAt = SyncCoding.date(from: entry.string("modifiedAt"))
        modifiedBy = UUID(uuidString: entry.string("modifiedBy"))
        extra = object.filter { !Self.knownKeys.contains($0.key) }
    }

    var json: SyncJSON {
        var object = extra
        object["category"] = .string(category.rawValue)
        object["title"] = .string(title)
        object["subtitle"] = .string(subtitle)
        object["favorite"] = .bool(favorite)
        object["tags"] = .array(tags.map(SyncJSON.string))
        object["urls"] = .array(urls.map(SyncJSON.string))
        object["match"] = .string(match.rawValue)
        object["trashedAt"] = trashedAt.map { .string(SyncCoding.string(from: $0)) } ?? .null
        object["modifiedAt"] = modifiedAt.map { .string(SyncCoding.string(from: $0)) } ?? .null
        object["modifiedBy"] = modifiedBy.map { .string($0.uuidString) } ?? .null
        return .object(object)
    }

    static func strings(_ json: SyncJSON?) -> [String] {
        guard case let .array(values)? = json else {
            return []
        }
        return values.compactMap {
            if case let .string(text) = $0 {
                return text
            }
            return nil
        }
    }
}
