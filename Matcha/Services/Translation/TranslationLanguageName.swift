import Foundation

/// Name of a language in the app's language (task 9.3). Pure type.
nonisolated enum TranslationLanguageName {
    /// For a label, capitalized: “German”, “Allemand”.
    static func of(_ language: Locale.Language) -> String {
        inSentence(language).capitalized(with: Locale.current)
    }

    /// As written inside a sentence: “French”, “français”, “Französisch”.
    static func inSentence(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
}
