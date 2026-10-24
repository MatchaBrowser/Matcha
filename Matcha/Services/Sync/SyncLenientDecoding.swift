import Foundation

/// Lenient reading of synced fields (`SYNC.md` § 2.9): a field that is missing, of the wrong type or outside the known
/// values is unreadable. Depending on the field, it takes its default value (`lenient`), or makes the whole record
/// ignored (`required`).
nonisolated extension KeyedDecodingContainer {
    /// The value, or nil if it is missing or unreadable.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// The value; throws if it is missing or unreadable: the record is ignored.
    func required<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        guard let value = lenient(type, forKey: key) else {
            throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [key], debugDescription: "Unreadable field"))
        }
        return value
    }

    /// Rank (`order`): a finite number, decimal allowed; 0 otherwise.
    func order(forKey key: Key) -> Double {
        lenient(Double.self, forKey: key).flatMap { $0.isFinite ? $0 : nil } ?? 0
    }
}

/// Ranks: a JSON number in sync (decimal allowed, `SYNC.md` § 2.7), an integer in Matcha's records. Pure type.
nonisolated enum SyncOrder {
    /// Integer rank of a received value, rounded and kept within a reasonable range.
    static func integer(_ value: Double) -> Int {
        Int(min(max(value.rounded(), -1_000_000_000), 1_000_000_000))
    }
}

/// Addresses that travel (`SYNC.md` § 2.4): http and https only, without user name nor password. Pure type.
nonisolated enum SyncWebURL {
    static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased())
    }

    /// `url` as it travels: nil if it is not a web address.
    static func shared(_ url: URL?) -> URL? {
        guard let url, isWeb(url) else {
            return nil
        }
        guard url.user != nil || url.password != nil, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.user = nil
        components.password = nil
        return components.url ?? url
    }
}
