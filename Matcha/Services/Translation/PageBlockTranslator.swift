import Foundation
import OSLog

/// Translates blocks of a page (task 9.1) with a method (`TranslationMethod`): in batches of bounded size
/// (`TranslationLimits`). The rich-text method only takes the blocks of several pieces (a link or bold text inside a
/// sentence), one at a time; the others go in batches, as plain text (faster), and so does a block whose rich
/// translation can't be shared out between its pieces, or that is too long. Gives the texts of each block's pieces, by
/// block; a block without words to translate is not in the result.
nonisolated struct PageBlockTranslator {
    let translator: any TextTranslating
    let method: TranslationMethod

    @concurrent func translate(_ blocks: [TranslationBlock]) async throws -> [TranslationBlock.ID: [String]] {
        let blocks = blocks.filter(\.needsTranslation)
        guard method == .richText, #available(macOS 26.4, *) else {
            return try await translatePlainText(blocks)
        }
        let rich = blocks.filter { block in
            block.pieces.count > 1 && block.pieces.reduce(0) { $0 + $1.text.count } <= TranslationLimits.maximumRichBlockLength
        }
        var texts = try await translateRichText(rich)
        let rest = blocks.filter { texts[$0.id] == nil }
        if !rest.isEmpty {
            Logger.translation.info("Rich-text method: \(rich.count - texts.count) of \(rich.count) blocks back to plain text")
            try await texts.merge(translatePlainText(rest)) { rich, _ in rich }
        }
        return texts
    }

    private func translatePlainText(_ blocks: [TranslationBlock]) async throws -> [TranslationBlock.ID: [String]] {
        let requests = PlainBlockTranslation.requests(for: blocks)
        var translations: [String?] = []
        for batch in TranslationLimits.batches(of: requests, length: \.text.count) {
            try await translations += translator.translate(batch.map(\.text))
        }
        return PlainBlockTranslation.texts(of: blocks, requests: requests, translations: translations)
    }

    /// The blocks whose translation could be shared out between their pieces.
    @available(macOS 26.4, *)
    private func translateRichText(_ blocks: [TranslationBlock]) async throws -> [TranslationBlock.ID: [String]] {
        var texts: [TranslationBlock.ID: [String]] = [:]
        let batches = TranslationLimits.batches(of: blocks) { $0.pieces.reduce(0) { $0 + $1.text.count } }
        for batch in batches {
            let translations = try await translator.translate(batch.map(RichBlockTranslation.source(for:)))
            for (block, translation) in zip(batch, translations) {
                if let translation, let pieces = RichBlockTranslation.texts(from: RichBlockTranslation.runs(of: translation), of: block) {
                    texts[block.id] = pieces
                }
            }
        }
        return texts
    }
}
