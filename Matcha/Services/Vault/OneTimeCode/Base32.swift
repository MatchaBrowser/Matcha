import Foundation

/// Base 32 of RFC 4648 (§ 6, alphabet `A–Z 2–7`), in which one-time code secrets are given (`VAULT.md` § 9.7).
/// Decoding ignores case, white space, hyphens and `=` padding, since secrets are typed or copied in groups; any other
/// character, or a length that no whole number of bytes gives (1, 3 or 6 characters past a multiple of 8), is refused.
/// Encoding writes uppercase letters, without padding. Pure type.
nonisolated enum Base32 {
    enum Error: Swift.Error, Equatable {
        /// A character outside the alphabet, other than white space, a hyphen or `=`.
        case invalidCharacter
        /// The number of characters can't come from whole bytes.
        case invalidLength
    }

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// `data` in base 32, uppercase, without padding.
    static func encode(_ data: Data) -> String {
        var characters: [Character] = []
        characters.reserveCapacity((data.count * 8 + 4) / 5)
        var accumulator = 0
        var bits = 0
        for byte in data {
            accumulator = (accumulator << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                characters.append(alphabet[(accumulator >> bits) & 31])
            }
            accumulator &= (1 << bits) - 1
        }
        if bits > 0 {
            characters.append(alphabet[(accumulator << (5 - bits)) & 31])
        }
        return String(characters)
    }

    /// The bytes of `text`; the bits left over after the last whole byte are dropped.
    static func decode(_ text: String) throws -> Data {
        var data = Data()
        var accumulator = 0
        var bits = 0
        var count = 0
        for character in text where !isIgnored(character) {
            guard let value = value(of: character) else {
                throw Error.invalidCharacter
            }
            accumulator = ((accumulator << 5) | value) & 0xFFFF
            bits += 5
            count += 1
            if bits >= 8 {
                bits -= 8
                data.append(UInt8((accumulator >> bits) & 0xFF))
            }
        }
        guard ![1, 3, 6].contains(count % 8) else {
            throw Error.invalidLength
        }
        return data
    }

    private static func isIgnored(_ character: Character) -> Bool {
        character.isWhitespace || character == "=" || character == "-"
    }

    /// The value (0 to 31) of a character of the alphabet, in either case; nil for any other.
    private static func value(of character: Character) -> Int? {
        guard let ascii = character.asciiValue else {
            return nil
        }
        return switch ascii {
        case UInt8(ascii: "A") ... UInt8(ascii: "Z"): Int(ascii - UInt8(ascii: "A"))
        case UInt8(ascii: "a") ... UInt8(ascii: "z"): Int(ascii - UInt8(ascii: "a"))
        case UInt8(ascii: "2") ... UInt8(ascii: "7"): Int(ascii - UInt8(ascii: "2")) + 26
        default: nil
        }
    }
}
