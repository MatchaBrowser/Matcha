import Foundation

/// How the blocks of a page are translated (task 9.1): rich text from macOS 26.4 (`RichBlockTranslation`), plain text
/// before (`PlainBlockTranslation`). Pure type.
nonisolated enum TranslationMethod: Equatable, Sendable {
    case plainText
    case richText

    /// Debug builds only: `-forcePlainTranslation YES` at launch gives the plain-text method on a recent Mac, to check it.
    static let forcePlainTextKey = "forcePlainTranslation"

    /// The method of this Mac, unless the plain-text one is forced.
    static func preferred(forcingPlainText: Bool = isPlainTextForced) -> TranslationMethod {
        if !forcingPlainText, #available(macOS 26.4, *) {
            return .richText
        }
        return .plainText
    }

    static var isPlainTextForced: Bool {
        TestEnvironment.arguments()?.bool(forKey: forcePlainTextKey) == true
    }
}
