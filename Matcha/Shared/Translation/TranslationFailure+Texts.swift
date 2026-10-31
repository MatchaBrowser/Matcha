import Foundation

extension TranslationFailure {
    /// What the translation popover says of the failure.
    var message: String {
        switch self {
        case .unsupportedLanguage:
            String(
                localized: "Matcha can't translate the language of this page.",
                comment: "Translation popover: the Mac can't translate the page's language",
            )
        case .unknownLanguage:
            String(
                localized: "Matcha couldn't recognize the language of this page.",
                comment: "Translation popover: the page's language wasn't recognized",
            )
        case .notDownloaded:
            String(
                localized: "The languages of this translation aren't downloaded yet. Try again once macOS has downloaded them.",
                comment: "Translation popover: the languages are being downloaded by macOS, or the download was declined",
            )
        case .nothingToTranslate:
            String(localized: "This page has no text to translate.", comment: "Translation popover: nothing to translate on the page")
        case .other:
            String(
                localized: "This page couldn't be translated.",
                comment: "Translation popover: the translation failed for another reason",
            )
        }
    }
}
