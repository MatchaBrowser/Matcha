import Foundation
@testable import Matcha
import Testing

/// Plain-text method (task 9.1): each piece with words translated alone, its edge spaces kept; the rest unchanged.
struct PlainBlockTranslationTests {
    @Test func `edge spaces are set apart from the text`() {
        let piece = EdgeWhitespace(" to read the ")
        #expect(piece == EdgeWhitespace(" to read the "))
        #expect(piece.leading == " ")
        #expect(piece.core == "to read the")
        #expect(piece.trailing == " ")
        #expect(piece.surrounding(" pour lire l’ ") == " pour lire l’ ")
        #expect(EdgeWhitespace("\n    Hello").leading == "\n    ")
        #expect(EdgeWhitespace("\n    Hello").trailing.isEmpty)
        #expect(EdgeWhitespace("   ").core.isEmpty)
        #expect(EdgeWhitespace("   ").leading == "   ")
        #expect(EdgeWhitespace("").surrounding("x") == "x")
    }

    @Test func `only the pieces with words are asked for, without their spaces`() {
        let long = String(repeating: "a", count: TranslationLimits.maximumPieceLength + 1)
        let blocks = [
            TranslationBlock.make(1, ["Click ", "this link", " — ", "2026", " ", "fetchData()", long], skipped: [5]),
            TranslationBlock.make(2, ["  A whole paragraph.  "]),
        ]
        #expect(PlainBlockTranslation.requests(for: blocks) == [
            .init(block: 1, piece: 0, text: "Click"),
            .init(block: 1, piece: 1, text: "this link"),
            .init(block: 2, piece: 0, text: "A whole paragraph."),
        ])
    }

    @Test func `translations go back in their pieces with the original spaces`() {
        let blocks = [TranslationBlock.make(1, ["Click ", "this link", " to read ", "fetchData()"], skipped: [3])]
        let requests = PlainBlockTranslation.requests(for: blocks)
        let texts = PlainBlockTranslation.texts(of: blocks, requests: requests, translations: ["Cliquez", " ce lien ", "pour lire"])
        #expect(texts == [1: ["Cliquez ", "ce lien", " pour lire ", "fetchData()"]])
    }

    @Test func `a piece not translated keeps its text`() {
        let blocks = [TranslationBlock.make(1, ["One ", "two ", "three"])]
        let requests = PlainBlockTranslation.requests(for: blocks)
        let texts = PlainBlockTranslation.texts(of: blocks, requests: requests, translations: [nil, "", "trois"])
        #expect(texts == [1: ["One ", "two ", "trois"]])
    }

    @Test func `fewer translations than requests leave the rest unchanged`() {
        let blocks = [TranslationBlock.make(1, ["One"]), TranslationBlock.make(2, ["Two"])]
        let requests = PlainBlockTranslation.requests(for: blocks)
        let texts = PlainBlockTranslation.texts(of: blocks, requests: requests, translations: ["Un"])
        #expect(texts == [1: ["Un"], 2: ["Two"]])
    }

    @Test func `a block needs translation only with words outside code`() {
        #expect(TranslationBlock.make(1, ["Hello"]).needsTranslation)
        #expect(TranslationBlock.make(1, ["Été"]).needsTranslation)
        #expect(!TranslationBlock.make(1, [" ", "2026", "—", "!"]).needsTranslation)
        #expect(!TranslationBlock.make(1, ["fetchData()"], skipped: [0]).needsTranslation)
    }

    @Test func `batches are bounded in count and in length`() {
        let counts = TranslationLimits.batches(of: Array(repeating: 1, count: 250)) { $0 }.map(\.count)
        #expect(counts == [100, 100, 50])
        let half = TranslationLimits.maximumBatchLength / 2
        let lengths = TranslationLimits.batches(of: [half, half, 1, TranslationLimits.maximumBatchLength * 2, 1]) { $0 }
        #expect(lengths == [[half, half], [1], [TranslationLimits.maximumBatchLength * 2], [1]])
        #expect(TranslationLimits.batches(of: [Int]()) { $0 }.isEmpty)
    }
}
