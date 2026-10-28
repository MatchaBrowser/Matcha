import Foundation
import Translation

/// Rich-text method (task 9.1), from macOS 26.4: a block is translated whole, as one sentence, with each piece marked
/// in the text sent (`TranslationPieceKey`) and the code marked `skipsTranslation`; the translation is shared out
/// between the pieces by those marks. When it can't be (`texts(from:of:)` gives nil), the block goes through the
/// plain-text method.
nonisolated enum RichBlockTranslation {
    /// A run of a translated block: its text and the piece it comes from (nil: its mark was lost).
    struct Run: Equatable, Sendable {
        let piece: Int?
        let text: String
    }

    /// Text sent for `block`: its pieces in order, each one marked.
    @available(macOS 26.4, *)
    static func source(for block: TranslationBlock) -> AttributedString {
        var source = AttributedString()
        for (index, piece) in block.pieces.enumerated() {
            var part = AttributedString(piece.text)
            part[TranslationPieceKey.self] = index
            if piece.skipsTranslation {
                part.translation.skipsTranslation = true
            }
            source += part
        }
        return source
    }

    /// The runs of `text` by piece, in order.
    static func runs(of text: AttributedString) -> [Run] {
        text.runs[TranslationPieceKey.self].map { piece, range in
            Run(piece: piece, text: String(text[range].characters))
        }
    }

    /// Texts of the pieces of `block` read from the runs of its translation; nil if they can't be shared out: text
    /// without its mark, pieces in another order or split, a piece with words gone, a skipped piece changed. Spaces
    /// without a mark go with the piece before them; a piece of spaces only may vanish. The whole translation of a
    /// block of one piece is that piece's, with or without its mark.
    static func texts(from runs: [Run], of block: TranslationBlock) -> [String]? {
        if block.pieces.count == 1, let piece = block.pieces.first, !piece.skipsTranslation {
            let text = runs.map(\.text).joined()
            return EdgeWhitespace(text).core.isEmpty ? nil : [EdgeWhitespace(piece.text).surrounding(text)]
        }
        var texts = [String?](repeating: nil, count: block.pieces.count)
        var current: Int?
        var pendingSpaces = ""
        for run in runs {
            guard let piece = run.piece else {
                guard run.text.allSatisfy(\.isWhitespace) else {
                    return nil
                }
                if let current {
                    texts[current]? += run.text
                } else {
                    pendingSpaces += run.text
                }
                continue
            }
            guard texts.indices.contains(piece) else {
                return nil
            }
            if piece == current {
                texts[piece]? += run.text
                continue
            }
            // Pieces come back in the order of the page, each in one stretch.
            guard texts[piece] == nil, current.map({ piece > $0 }) ?? true else {
                return nil
            }
            texts[piece] = pendingSpaces + run.text
            pendingSpaces = ""
            current = piece
        }
        return finished(texts, of: block)
    }

    /// Every piece with words is there; a skipped piece comes back unchanged, with its own spaces.
    private static func finished(_ texts: [String?], of block: TranslationBlock) -> [String]? {
        var result: [String] = []
        for (piece, text) in zip(block.pieces, texts) {
            let original = EdgeWhitespace(piece.text)
            let translated = text ?? ""
            if piece.skipsTranslation {
                guard EdgeWhitespace(translated).core == original.core else {
                    return nil
                }
                result.append(piece.text)
            } else if original.core.isEmpty {
                result.append(translated)
            } else {
                guard !EdgeWhitespace(translated).core.isEmpty else {
                    return nil
                }
                result.append(translated)
            }
        }
        return result
    }
}

/// Attribute of the rich-text method (task 9.1): the index of the piece a run of text comes from.
nonisolated enum TranslationPieceKey: AttributedStringKey {
    typealias Value = Int
    static let name = "com.matchabrowser.matcha.translationPiece"
}
