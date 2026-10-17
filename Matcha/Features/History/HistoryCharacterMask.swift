import Foundation

/// Lettres et chiffres présents dans un texte, sur 64 bits (a à z, 0 à 9, les autres répartis sur le reste) :
/// une adresse dont le masque ne contient pas celui du texte tapé ne peut pas lui correspondre. Sert à écarter
/// vite la plupart de l'historique à chaque frappe ; deux caractères peuvent partager un bit (le tri reste juste,
/// il écarte seulement moins).
nonisolated struct HistoryCharacterMask: Equatable, Sendable {
    private(set) var bits: UInt64 = 0

    init(_ texts: [String]) {
        for text in texts {
            // Forme composée : « é » s'écrit d'une seule façon des deux côtés.
            for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars where Self.counts(scalar) {
                bits |= 1 << Self.bit(for: scalar)
            }
        }
    }

    /// Vrai si chaque caractère de `other` est présent ici.
    func contains(_ other: Self) -> Bool {
        other.bits & ~bits == 0
    }

    private static func counts(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    private static func bit(for scalar: Unicode.Scalar) -> UInt64 {
        switch scalar.value {
        case 0x61 ... 0x7A: UInt64(scalar.value - 0x61)
        case 0x30 ... 0x39: 26 + UInt64(scalar.value - 0x30)
        default: 36 + UInt64(scalar.value % 28)
        }
    }
}
