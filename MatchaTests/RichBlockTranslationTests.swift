import Foundation
@testable import Matcha
import Testing
import Translation

/// Rich-text method (task 9.1): a block sent whole with its pieces marked; the translation shared out by those marks,
/// or refused (nil) when it can't be.
struct RichBlockTranslationTests {
    private typealias Run = RichBlockTranslation.Run

    private let block = TranslationBlock.make(1, ["Click ", "this link", " to read ", "fetchData()", "."], skipped: [3])

    @available(macOS 26.4, *)
    @Test func `each piece is marked and code is not translated`() {
        let source = RichBlockTranslation.source(for: block)
        #expect(String(source.characters) == "Click this link to read fetchData().")
        #expect(RichBlockTranslation.runs(of: source) == [
            Run(piece: 0, text: "Click "),
            Run(piece: 1, text: "this link"),
            Run(piece: 2, text: " to read "),
            Run(piece: 3, text: "fetchData()"),
            Run(piece: 4, text: "."),
        ])
        var skipped: [String] = []
        for run in source.runs where run[AttributeScopes.TranslationAttributes.SkipTranslationAttribute.self] == true {
            skipped.append(String(source[run.range].characters))
        }
        #expect(skipped == ["fetchData()"])
    }

    @Test func `a block of one piece takes the whole translation, marked or not`() {
        let block = TranslationBlock.make(1, ["\n  A whole paragraph. "])
        let runs = [Run(piece: nil, text: "Un paragraphe "), Run(piece: 0, text: "entier.")]
        #expect(RichBlockTranslation.texts(from: runs, of: block) == ["\n  Un paragraphe entier. "])
        #expect(RichBlockTranslation.texts(from: [Run(piece: nil, text: " ")], of: block) == nil)
        let code = TranslationBlock.make(1, ["fetchData()"], skipped: [0])
        #expect(RichBlockTranslation.texts(from: [Run(piece: 0, text: "fetchData()")], of: code) == ["fetchData()"])
    }

    @Test func `the runs of a translation are read by piece`() {
        var first = AttributedString("Cliquez sur ")
        first[TranslationPieceKey.self] = 0
        var second = AttributedString("ce lien")
        second[TranslationPieceKey.self] = 1
        let text = first + second + AttributedString(" !")
        #expect(RichBlockTranslation.runs(of: text) == [
            Run(piece: 0, text: "Cliquez sur "),
            Run(piece: 1, text: "ce lien"),
            Run(piece: nil, text: " !"),
        ])
    }

    @Test func `the translation is shared out between the pieces`() {
        let runs = [
            Run(piece: 0, text: "Cliquez sur "),
            Run(piece: 1, text: "ce lien"),
            Run(piece: 2, text: " pour lire "),
            Run(piece: 3, text: "fetchData()"),
            Run(piece: 4, text: "."),
        ]
        #expect(RichBlockTranslation.texts(from: runs, of: block) == ["Cliquez sur ", "ce lien", " pour lire ", "fetchData()", "."])
    }

    @Test func `runs of the same piece are joined, unmarked spaces go with the piece before`() {
        let block = TranslationBlock.make(1, ["The ", "red", " car"])
        let runs = [
            Run(piece: nil, text: " "),
            Run(piece: 0, text: "La"),
            Run(piece: nil, text: " "),
            Run(piece: 0, text: "voiture"),
            Run(piece: nil, text: " "),
            Run(piece: 1, text: "rouge"),
            Run(piece: 2, text: ""),
        ]
        // The car moved before the colour: a piece left empty would leave “ car” out, so the block is refused.
        #expect(RichBlockTranslation.texts(from: runs, of: block) == nil)
        let kept = runs.dropLast() + [Run(piece: 2, text: " là")]
        #expect(RichBlockTranslation.texts(from: Array(kept), of: block) == [" La voiture ", "rouge", " là"])
    }

    @Test func `pieces in another order are refused`() {
        let runs = [Run(piece: 1, text: "ce lien"), Run(piece: 0, text: "Cliquez sur ")]
        #expect(RichBlockTranslation.texts(from: runs, of: TranslationBlock.make(1, ["Click ", "this link"])) == nil)
    }

    @Test func `a piece split in two stretches is refused`() {
        let runs = [Run(piece: 0, text: "A "), Run(piece: 1, text: "B"), Run(piece: 0, text: " C")]
        #expect(RichBlockTranslation.texts(from: runs, of: TranslationBlock.make(1, ["One ", "two"])) == nil)
    }

    @Test func `words without their mark are refused`() {
        let runs = [Run(piece: 0, text: "Cliquez sur "), Run(piece: nil, text: "ce lien")]
        #expect(RichBlockTranslation.texts(from: runs, of: TranslationBlock.make(1, ["Click ", "this link"])) == nil)
    }

    @Test func `an unknown piece is refused`() {
        let runs = [Run(piece: 0, text: "Un"), Run(piece: 7, text: "deux")]
        #expect(RichBlockTranslation.texts(from: runs, of: TranslationBlock.make(1, ["One ", "two"])) == nil)
    }

    @Test func `a piece with words or digits must come back, a piece of spaces may vanish`() {
        let block = TranslationBlock.make(1, ["In ", "2026", " ", "Paris"])
        let withoutYear = [Run(piece: 0, text: "En "), Run(piece: 3, text: " Paris")]
        #expect(RichBlockTranslation.texts(from: withoutYear, of: block) == nil)
        let withoutSpace = [Run(piece: 0, text: "En "), Run(piece: 1, text: "2026"), Run(piece: 3, text: " Paris")]
        #expect(RichBlockTranslation.texts(from: withoutSpace, of: block) == ["En ", "2026", "", " Paris"])
    }

    @Test func `code comes back unchanged with its own spaces, or the block is refused`() {
        let block = TranslationBlock.make(1, ["Call ", " fetchData() ", "now"], skipped: [1])
        let kept = [Run(piece: 0, text: "Appelez "), Run(piece: 1, text: "fetchData()"), Run(piece: 2, text: " maintenant")]
        #expect(RichBlockTranslation.texts(from: kept, of: block) == ["Appelez ", " fetchData() ", " maintenant"])
        let changed = [Run(piece: 0, text: "Appelez "), Run(piece: 1, text: "chercherDonnées()"), Run(piece: 2, text: " maintenant")]
        #expect(RichBlockTranslation.texts(from: changed, of: block) == nil)
        let gone = [Run(piece: 0, text: "Appelez "), Run(piece: 2, text: " maintenant")]
        #expect(RichBlockTranslation.texts(from: gone, of: block) == nil)
    }
}
