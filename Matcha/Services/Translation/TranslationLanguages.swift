import Foundation
import Observation
import Translation

/// Languages of the translation (task 9.3): those the Mac can translate (`LanguageAvailability` of the translator the
/// pages use, `TranslationStrategy`, read once at launch)
/// and the one pages are translated into: the one the user chose (translation popover, page menu), otherwise the
/// first of the user's languages the Mac can translate into. The choice stays on this Mac (not synced). One for the
/// app (`AppEnvironment`), handed to the sessions (`SessionServices`).
@MainActor
@Observable
final class TranslationLanguages {
    static let chosenTargetKey = "translationTarget"

    /// Empty until read (`load`): every language is then taken as translatable.
    private(set) var supported: [Locale.Language] = []
    /// Language chosen by the user; nil: automatic.
    private(set) var chosen: Locale.Language?
    @ObservationIgnored private let preferred: [String]
    /// Where the choice is kept; nil: in memory only (tests).
    @ObservationIgnored private let defaults: UserDefaults?

    init(preferred: [String] = Locale.preferredLanguages, defaults: UserDefaults? = nil) {
        self.preferred = preferred
        self.defaults = defaults
        chosen = defaults?.string(forKey: Self.chosenTargetKey).flatMap(PageLanguage.declaredLanguage)
    }

    /// Language pages are translated into.
    var target: Locale.Language? {
        if let chosen, supported.isEmpty || supported.contains(where: { PageLanguage.isSame($0, chosen) }) {
            return chosen
        }
        return Self.target(preferred: preferred, supported: supported)
    }

    /// The target when nothing is chosen.
    var automaticTarget: Locale.Language? {
        Self.target(preferred: preferred, supported: supported)
    }

    /// Languages the Mac can translate into, one per language (`fr` for `fr` and `fr-CA`), by name.
    var choices: [Locale.Language] {
        var choices: [Locale.Language] = []
        for language in supported where !choices.contains(where: { PageLanguage.isSame($0, language) }) {
            choices.append(language)
        }
        return choices
            .sorted { TranslationLanguageName.of($0).localizedStandardCompare(TranslationLanguageName.of($1)) == .orderedAscending }
    }

    func load() async {
        supported = await Self.readSupported()
    }

    /// Pages are translated into `language` from now on; nil: back to automatic.
    func choose(_ language: Locale.Language?) {
        chosen = language
        if let language {
            defaults?.set(language.minimalIdentifier, forKey: Self.chosenTargetKey)
        } else {
            defaults?.removeObject(forKey: Self.chosenTargetKey)
        }
    }

    /// A page in `language` can be translated into the target: another language, that the Mac can translate.
    func canTranslate(from language: Locale.Language) -> Bool {
        guard let target, !PageLanguage.isSame(language, target) else {
            return false
        }
        return supported.isEmpty || supported.contains { PageLanguage.isSame($0, language) }
    }

    /// The first of `preferred` (the user's languages, in order) that is in `supported`, as `supported` names it;
    /// without a list, the first of `preferred`.
    nonisolated static func target(preferred: [String], supported: [Locale.Language]) -> Locale.Language? {
        let languages = preferred.map(Locale.Language.init(identifier:))
        guard !supported.isEmpty else {
            return languages.first
        }
        for language in languages {
            if let match = supported.first(where: { PageLanguage.isSame($0, language) }) {
                return match
            }
        }
        return nil
    }

    /// Languages of the translator the pages use (`TranslationStrategy`). The framework's object is not `Sendable`: made
    /// and read off the main actor.
    @concurrent private nonisolated static func readSupported() async -> [Locale.Language] {
        await TranslationStrategy.availability().supportedLanguages
    }
}
