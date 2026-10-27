import Foundation

/// What translates the texts of a page (task 9.1): a `TranslationSession` in the app (`SessionTextTranslator`), a fake
/// in the tests. Answers in the order of the texts; nil: that text was not translated.
nonisolated protocol TextTranslating {
    func translate(_ texts: [String]) async throws -> [String?]

    /// Rich-text method: the attributes of the texts sent may come back on their translation.
    @available(macOS 26.4, *)
    func translate(_ texts: [AttributedString]) async throws -> [AttributedString?]
}
