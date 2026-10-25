import Foundation
@testable import Matcha
import Testing
import WebKit

/// What WebKit does with blocking lists, which task 6.2 relies on (`DECISIONS.md`): an `ignore-previous-rules`
/// rule only acts within its own list (hence exceptions per page, and not a separate list of exceptions); a list
/// of more than 150,000 rules is rejected, then split by `BlocklistLoader`.
@MainActor
@Suite(.webKit)
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
    /// Exception for the test page (`obtest://pages/…`, domain “pages”), as a site exception would write it.
    private static let ignore = #"{"trigger":{"url-filter":".*","if-domain":["*pages"]},"action":{"type":"ignore-previous-rules"}}"#

    private func compile(_ identifier: String, _ rules: [String]) async throws -> WKContentRuleList {
        try await store.compile(identifier, rules: "[" + rules.joined(separator: ",") + "]")
    }

    /// Test page loaded in a view equipped with `lists`.
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
        // Separate exception list, set after as well as before: no effect on the other list.
        let exceptions = try await compile("exceptions", [Self.ignore])
        #expect(try await outcome(with: [rules, exceptions]) == .blocked)
        #expect(try await outcome(with: [exceptions, rules]) == .blocked)
    }

    /// Actual rejection by WebKit (150,001 rules), recognized, then list split into two parts that compile.
    @Test func `a list too big for WebKit is refused then split`() async throws {
        let count = RuleListSplitter.webKitMaximumRuleCount + 1
        let rules = "[" + Array(repeating: Self.block, count: count).joined(separator: ",") + "]"
        let refusal = await #expect(throws: (any Error).self) {
            try await store.compile("too-big", rules: rules)
        }
        #expect(refusal.map(ContentRuleListError.isTooManyRules) == true)

        var loader = BlocklistLoader(store: store) { _ in Data(rules.utf8) }
        // No splitting in advance: WebKit's rejection is what triggers it.
        loader.maximumRuleCount = .max
        let entry = BlocklistEntry(identifier: "big", name: "Big", version: "1", file: "big.json")
        let loaded = try #require(await loader.load([entry], previous: []).first)
        #expect(loaded.record.ruleCount == count)
        #expect(loaded.record.storeIdentifiers == ["matcha-blocklist.big.1.part-1", "matcha-blocklist.big.1.part-2"])
        #expect(loaded.ruleLists.count == 2)
    }
}
