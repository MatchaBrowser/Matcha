import Foundation

/// Blocks read from a page by the translation script (`PageTranslationScript`, task 9.2), checked with bounds: the page
/// may have changed the script's answer. Expected: `{blocks: [{id: Int, pieces: [[String, Bool]]}], remaining: Int}`.
/// A malformed block is left out (it stays in its language); a malformed answer gives nil. Pure type.
nonisolated struct PageTranslationBatch: Equatable, Sendable {
    let blocks: [TranslationBlock]
    /// Blocks still to read after these.
    let remaining: Int

    init(blocks: [TranslationBlock], remaining: Int) {
        self.blocks = blocks
        self.remaining = remaining
    }

    init?(scriptResult: Any?) {
        guard let fields = scriptResult as? [String: Any], let list = fields["blocks"] as? [Any] else {
            return nil
        }
        blocks = list.prefix(TranslationLimits.maximumBlocksPerCollect).compactMap(Self.block(from:))
        remaining = max(0, fields["remaining"] as? Int ?? 0)
    }

    private static func block(from value: Any) -> TranslationBlock? {
        guard let fields = value as? [String: Any], let id = fields["id"] as? Int, id > 0,
              let list = fields["pieces"] as? [Any], !list.isEmpty, list.count <= TranslationLimits.maximumPiecesPerBlock
        else {
            return nil
        }
        var pieces: [TranslationBlock.Piece] = []
        for item in list {
            guard let pair = item as? [Any], pair.count == 2, let text = pair[0] as? String,
                  text.utf16.count <= TranslationLimits.maximumPieceLength, let skipsTranslation = pair[1] as? Bool
            else {
                return nil
            }
            pieces.append(TranslationBlock.Piece(text, skipsTranslation: skipsTranslation))
        }
        return TranslationBlock(id: id, pieces: pieces)
    }
}
