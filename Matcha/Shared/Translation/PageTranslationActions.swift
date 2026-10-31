import Foundation

/// Translating a page or showing its original (task 9.3): the button next to the address, View > “Translate Page”
/// and the command bar go through here.
@MainActor
enum PageTranslationActions {
    /// A loaded web page or local file.
    static func canTranslate(_ page: BrowserTab?) -> Bool {
        guard let page, page.isLoaded, let scheme = page.documentURL?.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "file"].contains(scheme)
    }

    /// Translates `page` with the sessions of its window, from its language if known, into `language` (which becomes
    /// the target) or the target.
    static func translate(_ page: BrowserTab, host: TranslationHost, into language: Locale.Language? = nil) {
        if let language {
            host.languages.choose(language)
        }
        guard canTranslate(page), let webView = page.webView, let target = host.languages.target else {
            return
        }
        let pair = TranslationHost.Pair(source: page.translation.pageLanguage, target: target)
        page.translation.translate(in: webView) { [weak host] blocks in
            guard let host else {
                throw CancellationError()
            }
            return try await host.translate(blocks, pair: pair)
        }
    }

    static func showOriginal(_ page: BrowserTab) {
        Task { await page.translation.showOriginal() }
    }

    /// Translates `page`, or shows its original if it is translated.
    static func toggle(_ page: BrowserTab, host: TranslationHost) {
        if page.translation.isTranslated {
            showOriginal(page)
        } else {
            translate(page, host: host)
        }
    }
}
