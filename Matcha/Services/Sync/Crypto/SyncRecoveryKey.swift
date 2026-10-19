import Foundation

/// An account's recovery key (`SYNC.md` § 3.2): 20 random bytes, shown in Crockford's base 32 (32 characters in
/// 8 groups of 4, “7KQ2-M9XD-…”). When typed, spaces and hyphens are ignored, and so is case; `O` counts as `0`,
/// `I` and `L` count as `1`. Pure type.
nonisolated struct SyncRecoveryKey: Equatable, Sendable {
    static let byteCount = 20
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    let bytes: Data

    init?(bytes: Data) {
        guard bytes.count == Self.byteCount else {
            return nil
        }
        self.bytes = bytes
    }

    static func random() -> SyncRecoveryKey {
        SyncRecoveryKey(checkedBytes: SyncCrypto.randomBytes(byteCount))
    }

    private init(checkedBytes: Data) {
        bytes = checkedBytes
    }

    /// Key read from what the user typed; nil if it does not have 32 valid characters.
    init?(text: String) {
        var value: [UInt8] = []
        var accumulator = 0
        var bits = 0
        for character in text.uppercased() where character != "-" && !character.isWhitespace {
            let normalized: Character = switch character {
            case "O": "0"
            case "I", "L": "1"
            default: character
            }
            guard let digit = Self.alphabet.firstIndex(of: normalized) else {
                return nil
            }
            accumulator = (accumulator << 5) | digit
            bits += 5
            if bits >= 8 {
                bits -= 8
                value.append(UInt8((accumulator >> bits) & 0xFF))
            }
        }
        guard value.count == Self.byteCount, bits == 0 else {
            return nil
        }
        bytes = Data(value)
    }

    /// “810M-4GT4-…”: 32 characters in 8 groups of 4.
    var displayed: String {
        var characters: [Character] = []
        var accumulator = 0
        var bits = 0
        for byte in bytes {
            accumulator = (accumulator << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                characters.append(Self.alphabet[(accumulator >> bits) & 31])
            }
        }
        return stride(from: 0, to: characters.count, by: 4).map { String(characters[$0 ..< min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }
}
