import Foundation
import Observation
import OSLog
import WebKit

/// Translation of a page (tab, Peek, mini window; task 9.2): reads its blocks through its script
/// (`PageTranslationScript`), on screen first and in steps, has them translated, writes the translations; then
/// translates what the page adds or changes, as long as it stays translated. A new document, a released web view or a
/// terminated process bring the page back to its language (`reset`). Once a page has loaded, its language is read
/// (`PageLanguageScript`, task 9.3) to offer its translation.
@MainActor
@Observable
final class PageTranslation {
    enum State: Equatable {
        /// The page is in its own language.
        case original
        /// The first step of the translation is underway.
        case translating
        case translated
        /// The first pass failed: the page is partly translated at most.
        case failed(TranslationFailure)
    }

    /// Translates blocks: the translation session of the window (task 9.3), a fake in the tests.
    typealias Translate = @MainActor ([TranslationBlock]) async throws -> [TranslationBlock.ID: [String]]

    private(set) var state = State.original
    /// Language of the displayed document, once it has loaded; nil if unknown, or not a web page or a local file.
    private(set) var pageLanguage: Locale.Language?
    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var translate: Translate?
    /// Only the pass of the current translation writes into the page.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pass: Task<Void, Never>?
    /// The page changed during a pass: another one follows.
    @ObservationIgnored private var needsAnotherPass = false
    /// The page holds translations that `showOriginal` must take back (even after a failure).
    @ObservationIgnored private var hasWritten = false
    /// Only the language read from the current document counts.
    @ObservationIgnored private var document = 0

    /// The page shows (or is about to show) its translation.
    var isTranslated: Bool {
        state != .original
    }

    /// Translates the page of `webView` with `translate`; a page already translated is first put back in its language.
    func translate(in webView: WKWebView, using translate: @escaping Translate) {
        // The script may hold blocks of an earlier translation: they are put back first.
        let restoresFirst = (hasWritten || state != .original) && self.webView === webView
        reset()
        self.webView = webView
        self.translate = translate
        (webView as? BrowserWebView)?.translation = self
        state = .translating
        startPass(restoringFirst: restoresFirst)
    }

    /// Puts the page back in its language.
    func showOriginal() async {
        guard let webView, hasWritten || state != .original else {
            return
        }
        reset()
        do {
            try await PageTranslationScript.restore(in: webView)
        } catch {
            Logger.translation.error("Restoring the original text failed: \(error.logSummary, privacy: .public)")
        }
    }

    /// New document, web view released or process terminated: the page is in its language again (its script went
    /// with its document); what was underway is dropped.
    func reset() {
        if let webView = webView as? BrowserWebView, webView.translation === self {
            webView.translation = nil
        }
        generation += 1
        pass?.cancel()
        pass = nil
        translate = nil
        needsAnotherPass = false
        hasWritten = false
        state = .original
    }

    /// New document displayed: in its own language, which is not known yet.
    func documentDidChange() {
        reset()
        document += 1
        pageLanguage = nil
    }

    /// The document of `webView` has loaded: its language is read (web pages and local files only).
    func pageDidFinishLoading(in webView: WKWebView) {
        guard let scheme = webView.url?.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else {
            return
        }
        let document = document
        Task { [weak self] in
            let sample: PageLanguageSample?
            do {
                sample = try await PageLanguageScript.sample(in: webView)
            } catch {
                Logger.translation.notice("Reading the page's language failed: \(error.logSummary, privacy: .public)")
                return
            }
            guard let self, document == self.document else {
                return
            }
            pageLanguage = sample?.language
        }
    }

    /// The script saw new text in the translated page.
    func contentDidChange() {
        guard state == .translating || state == .translated, translate != nil else {
            return
        }
        if pass == nil {
            startPass(restoringFirst: false)
        } else {
            needsAnotherPass = true
        }
    }

    private func startPass(restoringFirst: Bool) {
        let generation = generation
        pass = Task { [weak self] in
            await self?.runPass(generation: generation, restoringFirst: restoringFirst)
            guard let self, generation == self.generation else {
                return
            }
            pass = nil
        }
    }

    private func runPass(generation: Int, restoringFirst: Bool) async {
        guard let webView, let translate else {
            return
        }
        do {
            if restoringFirst {
                try await PageTranslationScript.restore(in: webView)
            }
            repeat {
                needsAnotherPass = false
                guard try await translateBlocks(in: webView, with: translate, generation: generation) else {
                    return
                }
            } while needsAnotherPass
            // A first pass that found nothing to translate.
            state = hasWritten || state == .translated ? .translated : .failed(.nothingToTranslate)
        } catch {
            guard generation == self.generation else {
                return
            }
            Logger.translation.error("Page translation failed: \(error.logSummary, privacy: .public)")
            // A later pass that fails (new content) leaves the page translated.
            if state == .translating {
                state = .failed(TranslationFailure(error))
            }
        }
    }

    /// Translates the blocks still to translate, step by step; false if the translation was dropped meanwhile.
    private func translateBlocks(in webView: WKWebView, with translate: Translate, generation: Int) async throws -> Bool {
        while true {
            guard let batch = try await PageTranslationScript.collect(in: webView) else {
                throw PageTranslationScriptError.malformedAnswer
            }
            guard generation == self.generation else {
                return false
            }
            guard !batch.blocks.isEmpty else {
                return true
            }
            let texts = try await translate(batch.blocks)
            guard generation == self.generation else {
                return false
            }
            hasWritten = true
            try await PageTranslationScript.apply(texts, in: webView)
            // The blocks on screen come first: once written, the page shows its translation; the rest follows.
            if state == .translating {
                state = .translated
            }
            Logger.translation.info("Page translation: \(texts.count) of \(batch.blocks.count) blocks written")
            if batch.remaining == 0 {
                return generation == self.generation
            }
        }
    }
}

/// The translation script answered something else than blocks.
nonisolated enum PageTranslationScriptError: Error {
    case malformedAnswer
}
