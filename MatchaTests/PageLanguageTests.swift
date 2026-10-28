import Foundation
@testable import Matcha
import Testing
import Translation

/// Language of a page (task 9.3): recognized from its text, otherwise declared; target language; reasons of a failure;
/// what the language script reads, with bounds.
struct PageLanguageTests {
    private let testDefaults = TestDefaults("PageLanguageTests")
    private let english = "The quick brown fox jumps over the lazy dog while the children watch from the garden."
    private let french = "Le petit chat dort au soleil pendant que les enfants jouent dans le jardin de la maison."
    private let german = "Der schnelle braune Fuchs springt über den faulen Hund, während die Kinder im Garten spielen."

    @Test func `the text of the page wins over its declared language`() {
        #expect(PageLanguage.detect(declared: "en", sample: french)?.languageCode == "fr")
        #expect(PageLanguage.detect(declared: nil, sample: german)?.languageCode == "de")
        #expect(PageLanguage.detect(declared: "fr", sample: english)?.languageCode == "en")
    }

    @Test func `too little text gives the declared language`() {
        #expect(PageLanguage.detect(declared: "de-AT", sample: "Hallo")?.languageCode == "de")
        #expect(PageLanguage.detect(declared: nil, sample: "OK") == nil)
        #expect(PageLanguage.detect(declared: "", sample: "") == nil)
    }

    @Test func `a declared language must be a language`() {
        #expect(PageLanguage.declaredLanguage("en-US")?.languageCode == "en")
        #expect(PageLanguage.declaredLanguage(" fr_FR ")?.languageCode == "fr")
        #expect(PageLanguage.declaredLanguage("und") == nil)
        #expect(PageLanguage.declaredLanguage("x") == nil)
        #expect(PageLanguage.declaredLanguage("") == nil)
        #expect(PageLanguage.declaredLanguage(String(repeating: "a", count: 40)) == nil)
    }

    @Test func `same language whatever the region, not whatever the script`() {
        let language = Locale.Language.init(identifier:)
        #expect(PageLanguage.isSame(language("en-US"), language("en-GB")))
        #expect(PageLanguage.isSame(language("fr"), language("fr-CA")))
        #expect(!PageLanguage.isSame(language("en"), language("fr")))
        #expect(!PageLanguage.isSame(language("zh-Hans"), language("zh-Hant")))
        // `zh` is Simplified Chinese (`script` gives the likely script when the tag has none).
        #expect(PageLanguage.isSame(language("zh"), language("zh-Hans")))
        #expect(!PageLanguage.isSame(language("zh"), language("zh-TW")))
    }

    @Test func `the target is the first language of the user the Mac translates into`() {
        let supported = ["en", "fr", "de", "es"].map(Locale.Language.init(identifier:))
        #expect(TranslationLanguages.target(preferred: ["fr-FR", "en-US"], supported: supported)?.minimalIdentifier == "fr")
        #expect(TranslationLanguages.target(preferred: ["eu-ES", "en-GB"], supported: supported)?.minimalIdentifier == "en")
        #expect(TranslationLanguages.target(preferred: ["eu-ES"], supported: supported) == nil)
        #expect(TranslationLanguages.target(preferred: ["eu-ES"], supported: [])?.languageCode == "eu")
        #expect(TranslationLanguages.target(preferred: [], supported: supported) == nil)
    }

    @MainActor
    @Test func `a page in another language than the target can be translated`() {
        let languages = TranslationLanguages(preferred: ["fr-FR"])
        #expect(languages.canTranslate(from: Locale.Language(identifier: "en")))
        #expect(!languages.canTranslate(from: Locale.Language(identifier: "fr-CA")))
        #expect(!TranslationLanguages(preferred: []).canTranslate(from: Locale.Language(identifier: "en")))
    }

    @MainActor
    @Test func `a chosen target wins over the user's languages and is remembered`() {
        let defaults = testDefaults.make()
        let languages = TranslationLanguages(preferred: ["en-US"], defaults: defaults)
        #expect(languages.target?.languageCode == "en")
        languages.choose(Locale.Language(identifier: "fr"))
        #expect(languages.target?.languageCode == "fr")
        #expect(languages.automaticTarget?.languageCode == "en")
        #expect(TranslationLanguages(preferred: ["en-US"], defaults: defaults).target?.languageCode == "fr")
        languages.choose(nil)
        #expect(TranslationLanguages(preferred: ["en-US"], defaults: defaults).target?.languageCode == "en")
    }

    @MainActor
    @Test func `the choices are one per language`() async {
        let languages = TranslationLanguages(preferred: ["en-US"])
        #expect(languages.choices.isEmpty)
        await languages.load()
        let choices = languages.choices
        // The Mac's list (macOS 15 and later) has regional variants: one line each language.
        for (index, language) in choices.enumerated() {
            #expect(!choices[(index + 1)...].contains { PageLanguage.isSame($0, language) })
        }
        #expect(choices.contains { $0.languageCode == "fr" })
    }

    @Test func `failures are told apart`() {
        #expect(TranslationFailure(TranslationError.unsupportedLanguagePairing) == .unsupportedLanguage)
        #expect(TranslationFailure(TranslationError.unsupportedSourceLanguage) == .unsupportedLanguage)
        #expect(TranslationFailure(TranslationError.unableToIdentifyLanguage) == .unknownLanguage)
        #expect(TranslationFailure(TranslationError.nothingToTranslate) == .nothingToTranslate)
        #expect(TranslationFailure(CancellationError()) == .other)
        #expect(TranslationFailure(CocoaError(.userCancelled)) == .notDownloaded)
        if #available(macOS 26.0, *) {
            #expect(TranslationFailure(TranslationError.notInstalled) == .notDownloaded)
        }
    }

    @Test func `the sample of a page is read with bounds`() {
        let long = String(repeating: "word ", count: 1000)
        let sample = PageLanguageSample(scriptResult: ["lang": "fr", "text": long])
        #expect(sample?.declared == "fr")
        #expect(sample?.text.count == PageLanguageSample.maximumLength)
        #expect(PageLanguageSample(scriptResult: ["lang": String(repeating: "x", count: 50), "text": ""])?.declared == nil)
        #expect(PageLanguageSample(scriptResult: ["lang": "", "text": "Hello"])?.declared == nil)
        #expect(PageLanguageSample(scriptResult: ["lang": "en"]) == nil)
        #expect(PageLanguageSample(scriptResult: "text") == nil)
        #expect(PageLanguageSample(declared: nil, text: french).language?.languageCode == "fr")
    }
}
