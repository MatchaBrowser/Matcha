import Foundation

/// Clé de secours d'un compte (`SYNC.md` § 3.2) : 20 octets aléatoires, montrés en base 32 de Crockford (32 caractères
/// en 8 groupes de 4, « 7KQ2-M9XD-… »). À la saisie, espaces et tirets sont ignorés, la casse aussi ; `O` vaut `0`,
/// `I` et `L` valent `1`. Type pur.
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

    /// Clé lue dans ce que l'utilisateur a saisi ; nil si elle n'a pas 32 caractères valides.
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

    /// « 810M-4GT4-… » : 32 caractères en 8 groupes de 4.
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
