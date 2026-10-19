import Foundation
import Testing

/// Languages shipped in Matcha.app. Compiling the catalogs puts a `<language>.lproj` folder there per
/// language, with property lists: `Localizable.strings` (texts), `Localizable.stringsdict` (plurals)
/// and `InfoPlist.strings` (texts of the Info.plist). A language without a value for a key does not have
/// that key: macOS would then show the English text. English, the source language, only contains what
/// differs from the keys (the plurals): its other texts are the keys in the code and the Info.plist itself.
///
/// These tests only see the compiled app: they check that the languages agree with one another.
/// A key translated in no language (the case of a text just added to the code) or a translation
/// in the `new` or `needs_review` state (compiled like the others) is only caught by
/// `scripts/check-localizations.sh`, which reads the catalog: the test app is sandboxed and cannot.
struct LocalizationTests {
    static let sourceLanguage = "en"
    static let translations = ["fr", "de", "es", "it"]
    static let languages = [sourceLanguage] + translations
    /// Required plural categories (CLDR); “other” serves as the fallback for the others (many…).
    static let requiredPluralCategories = [
        "en": ["one", "other"], "fr": ["one", "other"], "de": ["one", "other"],
        "es": ["one", "other"], "it": ["one", "other"],
    ]

    @Test func `the app declares exactly its languages`() {
        #expect(Set(Bundle.main.localizations) == Set(Self.languages))
        #expect(Bundle.main.developmentLocalization == Self.sourceLanguage)
    }

    /// The keys present in at least one language must be present in all of them.
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

    // MARK: - Reading the bundle

    /// Compiled table of a language; empty if the language does not have this file.
    private static func table(_ name: String, _ type: String, _ language: String) throws -> [String: Any] {
        guard let url = Bundle.main.url(forResource: name, withExtension: type, subdirectory: nil, localization: language) else {
            return [:]
        }
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any], "\(language).lproj/\(name).\(type) illisible")
    }

    /// All the keys present in at least one language: each translation must have all of them.
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

    /// Info.plist texts shown by macOS (permissions), plus those translated in some language.
    private static func infoPlistKeys() throws -> Set<String> {
        let info = Bundle.main.infoDictionary ?? [:]
        var keys = Set(info.keys.filter { $0.hasPrefix("NS") && $0.hasSuffix("UsageDescription") })
        for language in translations {
            try keys.formUnion(table("InfoPlist", "strings", language).keys)
        }
        return keys
    }
}
