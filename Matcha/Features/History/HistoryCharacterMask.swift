import Foundation

/// Letters and digits present in a text, on 64 bits (a to z, 0 to 9, the others spread over the rest): an address
/// whose mask does not contain the typed text's mask cannot match it. Quickly rules out most of the history on each
/// keystroke; two characters may share a bit (the filtering stays correct, it just rules out less).
nonisolated struct HistoryCharacterMask: Equatable, Sendable {
    private(set) var bits: UInt64 = 0

    init(_ texts: [String]) {
        for text in texts {
            // Composed form: “é” is written the same way on both sides.
            for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars where Self.counts(scalar) {
                bits |= 1 << Self.bit(for: scalar)
            }
        }
    }

    /// True if every character of `other` is present here.
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
