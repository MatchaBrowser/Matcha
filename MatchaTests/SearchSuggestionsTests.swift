import Foundation
@testable import Matcha
import Testing

/// Adresses et lecture des suggestions de recherche (sans réseau).
struct SearchSuggestionsTests {
    private func parse(_ json: String, encoding: String? = "utf-8") throws -> [String] {
        try SearchSuggestionParser.parse(Data(json.utf8), textEncodingName: encoding)
    }

    @Test func `suggestion urls per engine`() {
        let encoded = "c%2B%2B%20%26%20caf%C3%A9"
        let urls = SearchEngine.allCases.map { $0.suggestionsURL(for: "c++ & café")?.absoluteString }
        #expect(urls == [
            "https://www.google.com/complete/search?client=firefox&ie=utf-8&oe=utf-8&q=\(encoded)",
            "https://duckduckgo.com/ac/?type=list&q=\(encoded)",
            "https://www.bing.com/osjson.aspx?query=\(encoded)",
        ])
    }

    @Test func `parses google duckduckgo and bing responses`() throws {
        let google = #"["pain",["pain au levain","pain perdu"],[],{"google:suggestsubtypes":[[512],[512]]}]"#
        #expect(try parse(google, encoding: "UTF-8") == ["pain au levain", "pain perdu"])
        #expect(try parse(#"["pain",["pain au chocolat","pain perdu"]]"#) == ["pain au chocolat", "pain perdu"])
        #expect(try parse(#"["pain",["pain au levain c\u0027est quoi"]]"#, encoding: nil) == ["pain au levain c'est quoi"])
    }

    @Test func `decodes a declared latin1 response`() throws {
        let data = try #require(#"["e",["été"]]"#.data(using: .isoLatin1))
        #expect(try SearchSuggestionParser.parse(data, textEncodingName: "iso-8859-1") == ["été"])
        #expect(throws: SearchSuggestionError.malformed) {
            try SearchSuggestionParser.parse(data, textEncodingName: "utf-8")
        }
    }

    @Test(arguments: [#"{"a":1}"#, "[]", #"["q"]"#, #"["q","x"]"#, "pas du json"])
    func `rejects malformed responses`(json: String) {
        #expect(throws: SearchSuggestionError.malformed) {
            try parse(json)
        }
    }

    @Test func `rejects invalid bytes`() {
        #expect(throws: SearchSuggestionError.malformed) {
            try SearchSuggestionParser.parse(Data([0x5B, 0x22, 0xC3, 0x28, 0x22, 0x5D]), textEncodingName: nil)
        }
    }

    @Test func `keeps trimmed non empty strings once and at most eight`() throws {
        let long = String(repeating: "x", count: 250)
        let json = #"["q",["a",1," b ","","A","c",null,"d","e","f","g","\#(long)","h","i"]]"#
        let suggestions = try parse(json)
        #expect(suggestions == ["a", "b", "c", "d", "e", "f", "g", String(repeating: "x", count: 200)])
        #expect(suggestions.count == SearchSuggestionParser.maximumCount)
    }

    @Test(arguments: suggestionPolicyCases)
    func policy(_ policyCase: SuggestionPolicyCase) {
        let context = CommandContext(isPrivate: policyCase.isPrivate, showsSearchSuggestions: policyCase.setting)
        let allowed = SearchSuggestionsProvider.allowsRequest(for: query(policyCase.text), context: context)
        #expect(allowed == policyCase.allowed, "\(policyCase)")
    }
}

/// Texte et contexte d'une demande de suggestions, et la décision attendue.
struct SuggestionPolicyCase: CustomTestStringConvertible, Sendable {
    let text: String
    var setting = true
    var isPrivate = false
    let allowed: Bool

    var testDescription: String {
        "\(text.prefix(20)) (\(text.count)) réglage \(setting) privé \(isPrivate) → \(allowed)"
    }
}

private let suggestionPolicyCases: [SuggestionPolicyCase] = [
    SuggestionPolicyCase(text: "pain au levain", allowed: true),
    SuggestionPolicyCase(text: "swift 6.4", allowed: true),
    SuggestionPolicyCase(text: String(repeating: "a", count: SearchSuggestionsProvider.maximumLength), allowed: true),
    SuggestionPolicyCase(text: "pain au levain", setting: false, allowed: false),
    SuggestionPolicyCase(text: "pain au levain", isPrivate: true, allowed: false),
    SuggestionPolicyCase(text: "", allowed: false),
    SuggestionPolicyCase(text: "   ", allowed: false),
    SuggestionPolicyCase(text: "apple.com", allowed: false),
    SuggestionPolicyCase(text: "localhost:3000", allowed: false),
    SuggestionPolicyCase(text: "https://x.y", allowed: false),
    SuggestionPolicyCase(text: "about:blank", allowed: false),
    // Lus comme des recherches, mais tapés comme des adresses (hôte local, chemin, e-mail).
    SuggestionPolicyCase(text: "intranet:8080", allowed: false),
    SuggestionPolicyCase(text: "nas:5000/photos", allowed: false),
    SuggestionPolicyCase(text: "wiki/rh", allowed: false),
    SuggestionPolicyCase(text: "me@example.com", allowed: false),
    SuggestionPolicyCase(text: "1/2 cup in grams", allowed: true),
    SuggestionPolicyCase(text: String(repeating: "a", count: SearchSuggestionsProvider.maximumLength + 1), allowed: false),
]
