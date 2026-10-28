import Foundation

/// The spaces around a piece of text (task 9.1): a translator returns its text without them, but between a link and
/// the rest of its sentence they keep the words apart. Pure type.
nonisolated struct EdgeWhitespace: Equatable, Sendable {
    let leading: String
    /// The text without its edge spaces: what is translated.
    let core: String
    let trailing: String

    init(_ text: String) {
        let start = text.firstIndex { !$0.isWhitespace } ?? text.endIndex
        let end = text[start...].lastIndex { !$0.isWhitespace }.map { text.index(after: $0) } ?? start
        leading = String(text[..<start])
        core = String(text[start ..< end])
        trailing = String(text[end...])
    }

    /// `translation` with the edge spaces of the original text in place of its own.
    func surrounding(_ translation: String) -> String {
        leading + translation.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
    }
}
