import Foundation

/// Plain-text method (task 9.1), the only one before macOS 26.4: each piece with words is translated alone, without
/// its edge spaces, which come back around its translation. A block of one piece is thus translated whole; a link
/// inside a sentence is translated apart from it (it stays a link, the sentence reads less naturally). Pure type.
nonisolated enum PlainBlockTranslation {
    /// A text to translate: a piece of a block, without its edge spaces.
    struct Request: Equatable, Sendable {
        let block: TranslationBlock.ID
        let piece: Int
        let text: String
    }

    /// The texts to translate in `blocks`, in order: pieces with words, not too long.
    static func requests(for blocks: [TranslationBlock]) -> [Request] {
        blocks.flatMap { block in
            block.pieces.enumerated().compactMap { index, piece -> Request? in
                let core = EdgeWhitespace(piece.text).core
                guard piece.needsTranslation, core.count <= TranslationLimits.maximumPieceLength else {
                    return nil
                }
                return Request(block: block.id, piece: index, text: core)
            }
        }
    }

    /// Texts of the pieces of `blocks` once `translations` (one per request, in order; nil: not translated) are put
    /// back: the other pieces, and those not translated, keep their text.
    static func texts(
        of blocks: [TranslationBlock],
        requests: [Request],
        translations: [String?],
    ) -> [TranslationBlock.ID: [String]] {
        var texts = Dictionary(blocks.map { ($0.id, $0.originalTexts) }, uniquingKeysWith: { first, _ in first })
        for (request, translation) in zip(requests, translations) {
            guard let translation, !translation.isEmpty, let pieces = texts[request.block],
                  pieces.indices.contains(request.piece)
            else {
                continue
            }
            texts[request.block]?[request.piece] = EdgeWhitespace(pieces[request.piece]).surrounding(translation)
        }
        return texts
    }
}
