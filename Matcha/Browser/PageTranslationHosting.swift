import Foundation

/// What translates the pages of a window (task 9.3): its translation sessions (`TranslationHost`, on the interface
/// side). The page's context menu reaches it through the web view (`BrowserWebView.translationHost`), given by the
/// window that shows it.
@MainActor
protocol PageTranslationHosting: AnyObject {
    /// Language the pages are translated into; nil: none the Mac can translate into.
    var targetLanguage: Locale.Language? { get }
    /// Languages the Mac can translate into, by name; empty while unknown.
    var languageChoices: [Locale.Language] { get }

    /// Translates `page` into `language`, which becomes the target; nil: into the target.
    func translate(_ page: BrowserTab, into language: Locale.Language?)
    func showOriginal(_ page: BrowserTab)
}
