import Foundation
import Translation

/// Why a page could not be translated (task 9.3), as the user is told. Pure type.
nonisolated enum TranslationFailure: Equatable, Sendable {
    /// The Mac can't translate this language, or into the target.
    case unsupportedLanguage
    /// The page's language could not be recognized.
    case unknownLanguage
    /// The languages are not downloaded: download declined, still underway in macOS (its window then closes as
    /// cancelled), or failed (told apart from macOS 26).
    case notDownloaded
    /// The page has no text to translate.
    case nothingToTranslate
    case other

    init(_ error: any Error) {
        if #available(macOS 26.0, *), TranslationError.notInstalled ~= error {
            self = .notDownloaded
            return
        }
        // macOS's download window closed without the languages (seen while macOS was still downloading them).
        if (error as NSError).domain == NSCocoaErrorDomain, (error as NSError).code == NSUserCancelledError {
            self = .notDownloaded
            return
        }
        switch error {
        case TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage:
            self = .unsupportedLanguage
        case TranslationError.unsupportedLanguagePairing:
            self = .unsupportedLanguage
        case TranslationError.unableToIdentifyLanguage:
            self = .unknownLanguage
        case TranslationError.nothingToTranslate:
            self = .nothingToTranslate
        default:
            self = .other
        }
    }
}
