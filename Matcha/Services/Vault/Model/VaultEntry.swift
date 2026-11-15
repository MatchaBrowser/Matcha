import Foundation

/// A JSON object whose known keys are read and written through accessors, and whose unknown keys are kept as they
/// came: a newer version of Matcha may add some, and this one sends them back untouched (`VAULT.md` § 9.3, `SYNC.md`
/// § 2.2). The base of credentials, custom fields and file references. Pure type.
nonisolated struct VaultEntry: Codable, Equatable, Hashable, Sendable {
    private(set) var values: [String: SyncJSON]

    init(_ values: [String: SyncJSON] = [:]) {
        self.values = values
    }

    init(from decoder: any Decoder) throws {
        values = try SyncJSON(from: decoder).objectValue
    }

    func encode(to encoder: any Encoder) throws {
        try SyncJSON.object(values).encode(to: encoder)
    }

    /// Its `id`, unique in the item and kept for its whole life: the merge pairs entries with it.
    var id: String {
        get { string("id") }
        set { set("id", newValue) }
    }

    /// The text at `key`; `""` when absent or of another type.
    func string(_ key: String) -> String {
        if case let .string(value)? = values[key] {
            return value
        }
        return ""
    }

    /// The whole number at `key`; nil when absent or not a whole number.
    func integer(_ key: String) -> Int? {
        if case let .number(value)? = values[key], value.rounded() == value, abs(value) < 1e15 {
            return Int(value)
        }
        return nil
    }

    func value(_ key: String) -> SyncJSON? {
        values[key]
    }

    /// Sets a text; an empty text removes the key.
    mutating func set(_ key: String, _ value: String) {
        values[key] = value.isEmpty ? nil : .string(value)
    }

    mutating func set(_ key: String, integer: Int?) {
        values[key] = integer.map { .number(Double($0)) }
    }

    mutating func set(_ key: String, json: SyncJSON?) {
        values[key] = json
    }

    /// Keys, sorted.
    var keys: [String] {
        values.keys.sorted()
    }
}

/// An identifier for a new entry of an item: short, random, unique enough within one item.
nonisolated enum VaultEntryID {
    static func make() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
    }
}
