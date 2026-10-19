import Foundation

/// Any JSON value (task 7.4): the fields (`fields`) of a synced record, kept as they are when they come from a newer
/// version of Matcha. Pure type.
nonisolated enum SyncJSON: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SyncJSON])
    case object([String: SyncJSON])

    static let emptyObject = SyncJSON.object([:])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SyncJSON].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: SyncJSON].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// `value` as JSON, with sync's conventions (dates to the millisecond).
    static func encoding(_ value: some Encodable) throws -> SyncJSON {
        try SyncCoding.decoder().decode(SyncJSON.self, from: SyncCoding.encoder().encode(value))
    }

    /// This value read as a `T`.
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try SyncCoding.decoder().decode(type, from: SyncCoding.encoder().encode(self))
    }

    /// Fields of an object; empty for any other value.
    var objectValue: [String: SyncJSON] {
        if case let .object(value) = self {
            return value
        }
        return [:]
    }

    /// This object completed with the keys of `base` it does not have: fields unknown to this version of Matcha,
    /// received from a newer one, are sent back along with a modification.
    func keepingUnknownKeys(of base: SyncJSON) -> SyncJSON {
        .object(objectValue.merging(base.objectValue) { mine, _ in mine })
    }
}
