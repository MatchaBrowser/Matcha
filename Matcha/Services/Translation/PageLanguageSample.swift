import Foundation

/// What the language script (`PageLanguageScript`, task 9.3) reads of a page: its declared language and the start of
/// its text, checked with bounds. Expected: `{lang: String, text: String}`; any other answer gives nil. Pure type.
nonisolated struct PageLanguageSample: Equatable, Sendable {
    /// Characters of text read, enough for the recognizer.
    static let maximumLength = 1500
    /// Longest `lang` attribute kept (a BCP 47 tag is short).
    static let maximumTagLength = 35

    let declared: String?
    let text: String

    init(declared: String?, text: String) {
        self.declared = declared
        self.text = text
    }

    init?(scriptResult: Any?) {
        guard let fields = scriptResult as? [String: Any], let text = fields["text"] as? String else {
            return nil
        }
        let tag = fields["lang"] as? String
        declared = tag.flatMap { $0.isEmpty || $0.count > Self.maximumTagLength ? nil : $0 }
        self.text = String(text.prefix(Self.maximumLength))
    }

    var language: Locale.Language? {
        PageLanguage.detect(declared: declared, sample: text)
    }
}
