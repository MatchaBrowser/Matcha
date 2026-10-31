import Foundation

/// An extension's name and badge as the interface shows them (review EX13): the extension chooses them, so they never
/// carry invisible characters that reorder the text around them, never run long, and a badge never covers what is next
/// to its button. Pure type.
nonisolated enum ExtensionDisplayName {
    static let maximumLength = 60
    static let maximumBadgeLength = 4

    /// `name` without control or format characters (bidirectional overrides, zero-width marks), its spaces collapsed,
    /// cut to `maximumLength` characters.
    static func cleaned(_ name: String) -> String {
        let visible = name.unicodeScalars.filter { ![.control, .format].contains($0.properties.generalCategory) }
        let words = String(String.UnicodeScalarView(visible)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.count > maximumLength ? String(words.prefix(maximumLength - 1)) + "…" : words
    }

    /// The badge's text, cleaned the same way, `maximumBadgeLength` characters at most.
    static func badge(_ text: String) -> String {
        String(cleaned(text).prefix(maximumBadgeLength))
    }
}
