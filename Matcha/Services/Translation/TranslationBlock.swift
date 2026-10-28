import Foundation

/// A block of a page to translate (task 9.1): a paragraph, a heading, a cell… Its pieces are its text nodes, in the
/// order of the page; a link or bold text inside a sentence is a piece of its own. The translation gives one text per
/// piece, so that each node keeps its element. Pure type.
nonisolated struct TranslationBlock: Identifiable, Equatable, Sendable {
    /// A text node of the block.
    struct Piece: Equatable, Sendable {
        let text: String
        /// Code, `translate="no"`: kept as it is, but part of the sentence.
        let skipsTranslation: Bool

        init(_ text: String, skipsTranslation: Bool = false) {
            self.text = text
            self.skipsTranslation = skipsTranslation
        }

        /// Has words to translate: not skipped, and not only spaces, digits or punctuation.
        var needsTranslation: Bool {
            !skipsTranslation && text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }
    }

    /// Given by the page's script: it puts each translation back in its block.
    let id: Int
    let pieces: [Piece]

    /// Has at least one piece with words to translate.
    var needsTranslation: Bool {
        pieces.contains(where: \.needsTranslation)
    }

    /// The pieces' texts, unchanged: what a block becomes when it can't be translated.
    var originalTexts: [String] {
        pieces.map(\.text)
    }
}
