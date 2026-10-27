import Foundation
@testable import Matcha
import Translation

/// Translator of the tests (task 9.1): upper-cases the texts by default, keeping the attributes of a rich text; records
/// the size of each batch it gets.
actor FakeTextTranslator: TextTranslating {
    struct Failure: Error {}

    private let plain: @Sendable (String) -> String?
    private let rich: @Sendable (AttributedString) -> AttributedString?
    private let fails: Bool
    private(set) var plainBatches: [Int] = []
    private(set) var richBatches: [Int] = []

    init(
        fails: Bool = false,
        plain: @escaping @Sendable (String) -> String? = { $0.uppercased() },
        rich: @escaping @Sendable (AttributedString) -> AttributedString? = FakeTextTranslator.uppercased,
    ) {
        self.fails = fails
        self.plain = plain
        self.rich = rich
    }

    func translate(_ texts: [String]) async throws -> [String?] {
        plainBatches.append(texts.count)
        if fails {
            throw Failure()
        }
        return texts.map(plain)
    }

    func translate(_ texts: [AttributedString]) async throws -> [AttributedString?] {
        richBatches.append(texts.count)
        if fails {
            throw Failure()
        }
        return texts.map(rich)
    }

    /// `text` upper-cased, run by run except code: each run keeps its attributes (a translator that keeps the marks).
    static func uppercased(_ text: AttributedString) -> AttributedString {
        var result = AttributedString()
        for run in text.runs {
            let original = String(text[run.range].characters)
            var part = AttributedString(skipsTranslation(run) ? original : original.uppercased())
            part.setAttributes(run.attributes)
            result += part
        }
        return result
    }

    private static func skipsTranslation(_ run: AttributedString.Runs.Run) -> Bool {
        guard #available(macOS 26.4, *) else {
            return false
        }
        return run[AttributeScopes.TranslationAttributes.SkipTranslationAttribute.self] == true
    }

    /// `text` upper-cased without any attribute (a translator that loses the marks).
    static func unmarked(_ text: AttributedString) -> AttributedString {
        AttributedString(String(text.characters).uppercased())
    }
}

extension TranslationBlock {
    /// Block of the tests: `pieces` as texts, those in `skipped` (by index) marked as code.
    static func make(_ id: Int, _ pieces: [String], skipped: Set<Int> = []) -> TranslationBlock {
        TranslationBlock(id: id, pieces: pieces.enumerated().map { Piece($1, skipsTranslation: skipped.contains($0)) })
    }
}
