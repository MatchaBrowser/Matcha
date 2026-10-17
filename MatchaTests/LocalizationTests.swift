import Foundation
import Testing

/// Langues livrées dans Matcha.app. La compilation des catalogues y met un dossier `<langue>.lproj`
/// par langue, avec des listes de propriétés : `Localizable.strings` (textes), `Localizable.stringsdict`
/// (pluriels) et `InfoPlist.strings` (textes de l'Info.plist). Une langue sans valeur pour une clé n'a
/// pas cette clé : macOS afficherait alors l'anglais. L'anglais, langue source, ne contient que ce qui
/// diffère des clés (les pluriels) : ses autres textes sont les clés du code et l'Info.plist lui-même.
///
/// Ces tests ne voient que l'app compilée : ils vérifient que les langues concordent entre elles.
/// Une clé traduite dans aucune langue (cas d'un texte qui vient d'être ajouté au code) ou une traduction
/// à l'état `new` ou `needs_review` (compilée comme les autres) n'est repérée que par
/// `scripts/check-localizations.sh`, qui lit le catalogue : l'app de test est sandboxée et ne le peut pas.
struct LocalizationTests {
    static let sourceLanguage = "en"
    static let translations = ["fr", "de", "es", "it"]
    static let languages = [sourceLanguage] + translations
    /// Catégories de pluriel exigées (CLDR) ; « other » sert de repli aux autres (many…).
    static let requiredPluralCategories = [
        "en": ["one", "other"], "fr": ["one", "other"], "de": ["one", "other"],
        "es": ["one", "other"], "it": ["one", "other"],
    ]

    @Test func `the app declares exactly its languages`() {
        #expect(Set(Bundle.main.localizations) == Set(Self.languages))
        #expect(Bundle.main.developmentLocalization == Self.sourceLanguage)
    }

    /// Les clés présentes dans une langue au moins doivent l'être dans toutes.
    @Test(arguments: translations)
    func `every text and plural is translated`(language: String) throws {
        let keys = try Set(Self.table("Localizable", "strings", language).keys)
            .union(Self.table("Localizable", "stringsdict", language).keys)
        let reference = try Self.localizableKeys()
        #expect(!reference.isEmpty)
        let missing = reference.subtracting(keys).sorted()
        #expect(missing.isEmpty, "Non traduit en \(language) : \(missing)")
        let empty = try Self.table("Localizable", "strings", language).filter { ($0.value as? String)?.isEmpty != false }
        #expect(empty.isEmpty, "Valeur vide en \(language) : \(empty.keys.sorted())")
    }

    @Test(arguments: languages)
    func `every plural has all its variants`(language: String) throws {
        let plurals = try Self.table("Localizable", "stringsdict", language)
        let missing = try Self.pluralKeys().subtracting(plurals.keys).sorted()
        #expect(missing.isEmpty, "Pluriel absent en \(language) : \(missing)")
        for (key, value) in plurals {
            let rules = try #require(value as? [String: Any], "Pluriel illisible en \(language) : \(key)")
            #expect(rules["NSStringLocalizedFormatKey"] is String, "\(key) en \(language)")
            let variables = rules.values.compactMap { $0 as? [String: Any] }
            #expect(!variables.isEmpty, "\(key) en \(language)")
            for variable in variables {
                for category in Self.requiredPluralCategories[language, default: ["other"]] {
                    #expect((variable[category] as? String)?.isEmpty == false, "\(key) sans « \(category) » en \(language)")
                }
            }
        }
    }

    @Test(arguments: translations)
    func `every Info.plist text is translated`(language: String) throws {
        let reference = try Self.infoPlistKeys()
        #expect(!reference.isEmpty)
        let values = try Self.table("InfoPlist", "strings", language)
        let missing = reference.filter { (values[$0] as? String)?.isEmpty != false }.sorted()
        #expect(missing.isEmpty, "Info.plist non traduit en \(language) : \(missing)")
    }

    @Test func `the Info.plist has its source texts`() throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let missing = try Self.infoPlistKeys().filter { (info[$0] as? String)?.isEmpty != false }.sorted()
        #expect(missing.isEmpty, "Info.plist sans texte anglais : \(missing)")
    }

    // MARK: - Lecture du bundle

    /// Table compilée d'une langue ; vide si la langue n'a pas ce fichier.
    private static func table(_ name: String, _ type: String, _ language: String) throws -> [String: Any] {
        guard let url = Bundle.main.url(forResource: name, withExtension: type, subdirectory: nil, localization: language) else {
            return [:]
        }
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any], "\(language).lproj/\(name).\(type) illisible")
    }

    /// Toutes les clés présentes dans au moins une langue : chaque traduction doit les avoir toutes.
    private static func localizableKeys() throws -> Set<String> {
        var keys = try pluralKeys()
        for language in languages {
            try keys.formUnion(table("Localizable", "strings", language).keys)
        }
        return keys
    }

    private static func pluralKeys() throws -> Set<String> {
        var keys = Set<String>()
        for language in languages {
            try keys.formUnion(table("Localizable", "stringsdict", language).keys)
        }
        return keys
    }

    /// Textes de l'Info.plist montrés par macOS (autorisations), plus ceux traduits dans une langue.
    private static func infoPlistKeys() throws -> Set<String> {
        let info = Bundle.main.infoDictionary ?? [:]
        var keys = Set(info.keys.filter { $0.hasPrefix("NS") && $0.hasSuffix("UsageDescription") })
        for language in translations {
            try keys.formUnion(table("InfoPlist", "strings", language).keys)
        }
        return keys
    }
}
