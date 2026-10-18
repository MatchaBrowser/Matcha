import Foundation

/// Valeur JSON quelconque (tâche 7.4) : les champs (`fields`) d'un enregistrement synchronisé, gardés tels quels quand
/// ils viennent d'une version plus récente de Matcha. Type pur.
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

    /// `value` en JSON, avec les conventions de la synchro (dates à la milliseconde).
    static func encoding(_ value: some Encodable) throws -> SyncJSON {
        try SyncCoding.decoder().decode(SyncJSON.self, from: SyncCoding.encoder().encode(value))
    }

    /// Cette valeur lue comme un `T`.
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try SyncCoding.decoder().decode(type, from: SyncCoding.encoder().encode(self))
    }

    /// Champs d'un objet ; vide pour une autre valeur.
    var objectValue: [String: SyncJSON] {
        if case let .object(value) = self {
            return value
        }
        return [:]
    }

    /// Cet objet complété par les clés de `base` qu'il n'a pas : les champs inconnus de cette version de Matcha, reçus
    /// d'une plus récente, repartent avec une modification.
    func keepingUnknownKeys(of base: SyncJSON) -> SyncJSON {
        .object(objectValue.merging(base.objectValue) { mine, _ in mine })
    }
}
