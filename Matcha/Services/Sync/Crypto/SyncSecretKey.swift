import CryptoKit
import Foundation

/// An account's Secret Key (`SYNC.md` § 3.2): 16 random bytes, mixed with the master key so that `authKey` lets no one
/// test passwords, not even the server. Shown as “S1-” then, in Crockford's base 32 and 8 groups of 4, its 16 bytes
/// followed by the first 4 bytes of their SHA-256 (“S1-R30W-5GY4-…”). When typed, it is read like a recovery key
/// (`SyncRecoveryKey`), the “S1” prefix is optional, and a wrong checksum makes it invalid: a typing mistake is caught
/// on this Mac, not taken by the server for a wrong password. Kept in this Mac's keychain, never sent. Pure type.
nonisolated struct SyncSecretKey: Equatable, Sendable {
    static let byteCount = 16
    private static let checksumCount = 4
    private static let prefix = "S1"
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    let bytes: Data

    init?(bytes: Data) {
        guard bytes.count == Self.byteCount else {
            return nil
        }
        self.bytes = bytes
    }

    static func random() -> SyncSecretKey {
        SyncSecretKey(checkedBytes: SyncCrypto.randomBytes(byteCount))
    }

    private init(checkedBytes: Data) {
        bytes = checkedBytes
    }

    /// Key read from what the user typed; nil if a character is invalid, the length is wrong or the checksum doesn't
    /// match.
    init?(text: String) {
        guard var digits = Self.digits(of: text) else {
            return nil
        }
        if digits.count == 34, digits.prefix(2) == Self.digits(of: Self.prefix)?[...] {
            digits.removeFirst(2)
        }
        guard digits.count == 32 else {
            return nil
        }
        var value: [UInt8] = []
        var accumulator = 0
        var bits = 0
        for digit in digits {
            accumulator = (accumulator << 5) | digit
            bits += 5
            if bits >= 8 {
                bits -= 8
                value.append(UInt8((accumulator >> bits) & 0xFF))
            }
        }
        let key = Data(value.prefix(Self.byteCount))
        guard Data(value.suffix(Self.checksumCount)) == Self.checksum(of: key) else {
            return nil
        }
        bytes = key
    }

    /// The values of the typed characters, separators left out: case ignored, `O` counts as `0`, `I` and `L` as `1`;
    /// nil if a character is not in the alphabet.
    private static func digits(of text: String) -> [Int]? {
        var digits: [Int] = []
        for character in text.uppercased() where character != "-" && !character.isWhitespace {
            let normalized: Character = switch character {
            case "O": "0"
            case "I", "L": "1"
            default: character
            }
            guard let digit = alphabet.firstIndex(of: normalized) else {
                return nil
            }
            digits.append(digit)
        }
        return digits
    }

    /// “S1-R30W-5GY4-…”: the prefix, then 32 characters in 8 groups of 4.
    var displayed: String {
        var characters: [Character] = []
        var accumulator = 0
        var bits = 0
        for byte in bytes + Self.checksum(of: bytes) {
            accumulator = (accumulator << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                characters.append(Self.alphabet[(accumulator >> bits) & 31])
            }
        }
        let groups = stride(from: 0, to: characters.count, by: 4).map { String(characters[$0 ..< min($0 + 4, characters.count)]) }
        return ([Self.prefix] + groups).joined(separator: "-")
    }

    /// The first 4 bytes of SHA-256 of the key.
    static func checksum(of key: Data) -> Data {
        Data(SHA256.hash(data: key).prefix(checksumCount))
    }

    /// The typed text has the length of a Secret Key but isn't one: “The Secret Key is incorrect.”
    static func isMistyped(_ text: String) -> Bool {
        text.count(where: { $0 != "-" && !$0.isWhitespace }) >= 32 && SyncSecretKey(text: text) == nil
    }
}
