import Foundation
@testable import Matcha
import Testing

/// Translation of a page's blocks (task 9.1): the method of the Mac, batches, fallback of the rich-text method to the
/// plain-text one, and the answers of a `TranslationSession` matched by identifier.
struct PageBlockTranslatorTests {
    private let blocks = [
        TranslationBlock.make(1, ["Click ", "this link", " to read ", "fetchData()", "."], skipped: [3]),
        TranslationBlock.make(2, ["  2026  "]),
        TranslationBlock.make(3, ["A whole paragraph."]),
    ]

    @Test func `the plain-text method translates each piece with words`() async throws {
        let translator = FakeTextTranslator()
        let texts = try await PageBlockTranslator(translator: translator, method: .plainText).translate(blocks)
        #expect(texts == [
            1: ["CLICK ", "THIS LINK", " TO READ ", "fetchData()", "."],
            3: ["A WHOLE PARAGRAPH."],
        ])
        #expect(await translator.plainBatches == [4])
        #expect(await translator.richBatches.isEmpty)
    }

    @Test func `the plain-text method sends bounded batches`() async throws {
        let translator = FakeTextTranslator()
        let many = (0 ..< 150).map { TranslationBlock.make($0, ["Word \($0)"]) }
        let texts = try await PageBlockTranslator(translator: translator, method: .plainText).translate(many)
        #expect(texts.count == 150)
        #expect(texts[149] == ["WORD 149"])
        #expect(await translator.plainBatches == [100, 50])
    }

    @available(macOS 26.4, *)
    @Test func `the rich-text method sends a block of several pieces whole, the others in batches`() async throws {
        let translator = FakeTextTranslator()
        let texts = try await PageBlockTranslator(translator: translator, method: .richText).translate(blocks)
        #expect(texts == [
            1: ["CLICK ", "THIS LINK", " TO READ ", "fetchData()", "."],
            3: ["A WHOLE PARAGRAPH."],
        ])
        #expect(await translator.richBatches == [1])
        #expect(await translator.plainBatches == [1])
    }

    @available(macOS 26.4, *)
    @Test func `marks lost send the block through the plain-text method`() async throws {
        let translator = FakeTextTranslator(rich: FakeTextTranslator.unmarked)
        let texts = try await PageBlockTranslator(translator: translator, method: .richText).translate(blocks)
        #expect(texts[1] == ["CLICK ", "THIS LINK", " TO READ ", "fetchData()", "."])
        #expect(texts[3] == ["A WHOLE PARAGRAPH."])
        // The block of several pieces, then, in plain text, its pieces with the block of one piece.
        #expect(await translator.richBatches == [1])
        #expect(await translator.plainBatches == [4])
    }

    @available(macOS 26.4, *)
    @Test func `a block too long for the rich-text method goes through the plain-text one`() async throws {
        let translator = FakeTextTranslator()
        let pieces = Array(repeating: "Some words here. ", count: TranslationLimits.maximumRichBlockLength / 10)
        let long = TranslationBlock.make(9, pieces)
        let texts = try await PageBlockTranslator(translator: translator, method: .richText).translate([long])
        #expect(texts[9]?.first == "SOME WORDS HERE. ")
        #expect(await translator.richBatches.isEmpty)
        #expect(await translator.plainBatches.reduce(0, +) == pieces.count)
    }

    @Test func `a failure of the translator is passed on`() async {
        let translator = FakeTextTranslator(fails: true)
        await #expect(throws: FakeTextTranslator.Failure.self) {
            try await PageBlockTranslator(translator: translator, method: .preferred()).translate(blocks)
        }
    }

    @Test func `the method is rich text from macOS 26.4 unless plain text is forced`() {
        #expect(TranslationMethod.preferred(forcingPlainText: true) == .plainText)
        if #available(macOS 26.4, *) {
            #expect(TranslationMethod.preferred(forcingPlainText: false) == .richText)
        } else {
            #expect(TranslationMethod.preferred(forcingPlainText: false) == .plainText)
        }
    }

    @Test func `answers of a session are matched by identifier`() {
        let answers = SessionTextTranslator.answers(count: 3, responses: [("2", "c"), ("0", "a"), ("9", "x"), (nil, "y"), ("b", "z")])
        #expect(answers == ["a", nil, "c"])
    }
}
