import Foundation

/// A saved value read leniently (audit R4): nil if it can't be read, so that a list or a dictionary keeps its readable
/// entries instead of losing them all to one. Pure type.
nonisolated struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension Lenient: Sendable where Value: Sendable {}
