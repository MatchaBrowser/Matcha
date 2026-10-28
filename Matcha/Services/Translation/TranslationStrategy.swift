import Foundation
import Translation

/// Which of Apple's translators the pages use (task 9.3): from macOS 26.4, the “low latency” one, the classic
/// translation model of Safari and the Translate app, rather than the default “high fidelity” one, a generative model
/// (Apple Intelligence) about ten times slower (measured: 0.45 s a sentence). It has its own files: macOS asks to
/// download them at the first translation. Before macOS 26.4 there is only one translator.
nonisolated enum TranslationStrategy {
    /// Session configuration of a language pair.
    static func configuration(source: Locale.Language?, target: Locale.Language) -> TranslationSession.Configuration {
        if #available(macOS 26.4, *) {
            return TranslationSession.Configuration(source: source, target: target, preferredStrategy: .lowLatency)
        }
        return TranslationSession.Configuration(source: source, target: target)
    }

    /// Languages of that translator.
    static func availability() -> LanguageAvailability {
        if #available(macOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: .lowLatency)
        }
        return LanguageAvailability()
    }
}
