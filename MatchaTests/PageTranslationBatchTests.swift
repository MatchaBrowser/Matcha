import Foundation
@testable import Matcha
import Testing

/// Answer of the translation script (task 9.2), read with bounds: a malformed block is left out, a malformed answer
/// refused.
struct PageTranslationBatchTests {
    private func block(_ id: Any, _ pieces: [Any]) -> [String: Any] {
        ["id": id, "pieces": pieces]
    }

    @Test func `blocks and their pieces are read`() {
        let answer: [String: Any] = [
            "blocks": [block(3, [["Click ", false], ["this link", false], ["fetchData()", true]])],
            "remaining": 12,
        ]
        let batch = PageTranslationBatch(scriptResult: answer)
        #expect(batch == PageTranslationBatch(
            blocks: [TranslationBlock.make(3, ["Click ", "this link", "fetchData()"], skipped: [2])],
            remaining: 12,
        ))
    }

    @Test func `a malformed answer is refused`() {
        #expect(PageTranslationBatch(scriptResult: nil) == nil)
        #expect(PageTranslationBatch(scriptResult: "blocks") == nil)
        #expect(PageTranslationBatch(scriptResult: ["remaining": 1]) == nil)
        #expect(PageTranslationBatch(scriptResult: ["blocks": "none"]) == nil)
    }

    @Test func `a missing or negative remaining count is zero`() {
        #expect(PageTranslationBatch(scriptResult: ["blocks": []])?.remaining == 0)
        #expect(PageTranslationBatch(scriptResult: ["blocks": [], "remaining": -4])?.remaining == 0)
        #expect(PageTranslationBatch(scriptResult: ["blocks": [], "remaining": "many"])?.remaining == 0)
    }

    @Test func `a malformed block is left out, the others are kept`() {
        let tooMany = Array(repeating: ["word ", false] as [Any], count: TranslationLimits.maximumPiecesPerBlock + 1)
        let tooLong = String(repeating: "a", count: TranslationLimits.maximumPieceLength + 1)
        let answer: [String: Any] = ["blocks": [
            block(0, [["Zero", false]]),
            block(-2, [["Negative", false]]),
            block("4", [["Text id", false]]),
            block(5, []),
            block(6, tooMany),
            block(7, [[tooLong, false]]),
            block(8, [["Three", false, "extra"]]),
            block(9, [["No flag"]]),
            block(10, [[42, false]]),
            ["pieces": [["No id", false]]],
            "not a block",
            block(11, [["Kept", false]]),
        ]]
        #expect(PageTranslationBatch(scriptResult: answer)?.blocks == [TranslationBlock.make(11, ["Kept"])])
    }

    @Test func `no more blocks than a step allows`() {
        let blocks = (1 ... TranslationLimits.maximumBlocksPerCollect + 5).map { block($0, [["Word", false]]) }
        let batch = PageTranslationBatch(scriptResult: ["blocks": blocks, "remaining": 0])
        #expect(batch?.blocks.count == TranslationLimits.maximumBlocksPerCollect)
        #expect(batch?.blocks.last?.id == TranslationLimits.maximumBlocksPerCollect)
    }
}
