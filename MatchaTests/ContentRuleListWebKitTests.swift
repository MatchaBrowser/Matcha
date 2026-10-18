import Foundation
@testable import Matcha
import Testing
import WebKit

/// Ce que fait WebKit des listes de blocage, sur lequel repose la tâche 6.2 (`DECISIONS.md`) : une règle
/// `ignore-previous-rules` n'agit que dans sa propre liste (d'où des exceptions par page, et non une liste d'exceptions
/// à part) ; une liste de plus de 150 000 règles est refusée, puis découpée par `BlocklistLoader`.
@MainActor
final class ContentRuleListWebKitTests {
    private let store: WKContentRuleListStore
    private let directory: URL

    init() throws {
        (store, directory) = try BlockerTestPages.temporaryStore()
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private static let block = #"{"trigger":{"url-filter":"^obtest://blocked\\.test/"},"action":{"type":"block"}}"#
    private static let hide = #"{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".ad"}}"#
    /// Exception de la page d'essai (`obtest://pages/…`, domaine « pages »), comme une exception de site l'écrirait.
    private static let ignore = #"{"trigger":{"url-filter":".*","if-domain":["*pages"]},"action":{"type":"ignore-previous-rules"}}"#

    private func compile(_ identifier: String, _ rules: [String]) async throws -> WKContentRuleList {
        try await store.compile(identifier, rules: "[" + rules.joined(separator: ",") + "]")
    }

    /// Page d'essai chargée dans une vue munie de `lists`.
    private func outcome(with lists: [WKContentRuleList]) async throws -> BlockerTestPages.Outcome {
        let configuration = TestPages.configuration()
        lists.forEach(configuration.userContentController.add)
        let tab = BrowserTab(configuration: configuration)
        tab.load(BlockerTestPages.url())
        return try await BlockerTestPages.outcome(of: tab)
    }

    @Test func `ignore previous rules only acts within its own list`() async throws {
        let rules = try await compile("rules", [Self.block, Self.hide])
        #expect(try await outcome(with: [rules]) == .blocked)
        let sameList = try await compile("same-list", [Self.block, Self.hide, Self.ignore])
        #expect(try await outcome(with: [sameList]) == .open)
        // Liste d'exceptions à part, posée après comme avant : sans effet sur l'autre liste.
        let exceptions = try await compile("exceptions", [Self.ignore])
        #expect(try await outcome(with: [rules, exceptions]) == .blocked)
        #expect(try await outcome(with: [exceptions, rules]) == .blocked)
    }

    /// Refus réel de WebKit (150 001 règles), reconnu, puis liste découpée en deux parts qui se compilent.
    @Test func `a list too big for WebKit is refused then split`() async throws {
        let count = RuleListSplitter.webKitMaximumRuleCount + 1
        let rules = "[" + Array(repeating: Self.block, count: count).joined(separator: ",") + "]"
        let refusal = await #expect(throws: (any Error).self) {
            try await store.compile("too-big", rules: rules)
        }
        #expect(refusal.map(ContentRuleListError.isTooManyRules) == true)

        var loader = BlocklistLoader(store: store) { _ in Data(rules.utf8) }
        // Sans découpe d'avance : c'est le refus de WebKit qui la déclenche.
        loader.maximumRuleCount = .max
        let entry = BlocklistEntry(identifier: "big", name: "Big", version: "1", file: "big.json")
        let loaded = try #require(await loader.load([entry], previous: []).first)
        #expect(loaded.record.ruleCount == count)
        #expect(loaded.record.storeIdentifiers == ["matcha-blocklist.big.1.part-1", "matcha-blocklist.big.1.part-2"])
        #expect(loaded.ruleLists.count == 2)
    }
}
