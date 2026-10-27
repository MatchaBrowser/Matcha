import Foundation
import NaturalLanguage

/// Language of a page (task 9.3): recognized on the Mac (`NLLanguageRecognizer`) from a sample of its text, otherwise
/// the language it declares (`lang` attribute), which pages often leave at a template's value. Pure type.
nonisolated enum PageLanguage {
    /// Fewest letters for the recognizer to be trusted.
    static let minimumLetters = 40
    /// Lowest probability of the recognizer's best guess for it to be trusted.
    static let minimumConfidence = 0.6

    static func detect(declared: String?, sample: String) -> Locale.Language? {
        let letters = sample.unicodeScalars.lazy.filter { CharacterSet.letters.contains($0) }.count
        if letters >= minimumLetters {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(sample)
            let best = recognizer.languageHypotheses(withMaximum: 1).first
            if let best, best.value >= minimumConfidence, best.key != .undetermined {
                return Locale.Language(identifier: best.key.rawValue)
            }
        }
        return declaredLanguage(declared)
    }

    /// Language of a `lang` attribute (a BCP 47 tag); nil if empty, undetermined (`und`) or not a language.
    static func declaredLanguage(_ tag: String?) -> Locale.Language? {
        guard let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty, tag.count <= 35 else {
            return nil
        }
        let language = Locale.Language(identifier: tag.replacingOccurrences(of: "_", with: "-"))
        guard let code = language.languageCode?.identifier, (2 ... 3).contains(code.count), code != "und" else {
            return nil
        }
        return language
    }

    /// Same language, whatever the region (`en-US` and `en-GB`); two scripts (`zh-Hans`, `zh-Hant`) are two languages. A
    /// tag without a script has its likely one (`zh` is `zh-Hans`).
    static func isSame(_ first: Locale.Language, _ second: Locale.Language) -> Bool {
        guard first.languageCode == second.languageCode, first.languageCode != nil else {
            return false
        }
        guard let firstScript = first.script, let secondScript = second.script else {
            return true
        }
        return firstScript == secondScript
    }
}
