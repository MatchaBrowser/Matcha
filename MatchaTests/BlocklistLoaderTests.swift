import Foundation
@testable import Matcha
import Testing
import WebKit

/// In-memory list store: a compiled list is its JSON. Like WebKit, it rejects a list of more than
/// `maximumRuleCount` rules, and any list that contains “invalide”.
@MainActor
final class FakeRuleListStore: ContentRuleListStoring {
    private(set) var lists: [String: String] = [:]
    private(set) var compiled: [String] = []
    private(set) var removed: [String] = []
    var maximumRuleCount = Int.max

    init(lists: [String: String] = [:]) {
        self.lists = lists
    }

    func lookUp(_ identifier: String) async -> String? {
        lists[identifier]
    }

    func compile(_ identifier: String, rules: String) async throws -> String {
        compiled.append(identifier)
        let count = (try? JSONSerialization.jsonObject(with: Data(rules.utf8)) as? [Any])?.count ?? 0
        if count > maximumRuleCount {
            throw NSError(
                domain: WKError.errorDomain,
                code: WKError.Code.contentRuleListStoreCompileFailed.rawValue,
                userInfo: [NSHelpAnchorErrorKey: "Rule list compilation failed: Too many rules in JSON array."],
            )
        }
        if rules.contains("invalide") {
            throw NSError(
                domain: WKError.errorDomain,
                code: WKError.Code.contentRuleListStoreCompileFailed.rawValue,
                userInfo: [NSHelpAnchorErrorKey: "Rule list compilation failed: Invalid url-filter object."],
            )
        }
        lists[identifier] = rules
        return rules
    }

    func identifiers() async -> [String] {
        lists.keys.sorted()
    }

    func remove(_ identifier: String) async throws {
        removed.append(identifier)
        lists[identifier] = nil
    }
}

/// Preparation of the lists (task 6.2) with a fake store: compilation on first launch, reuse afterwards,
/// new version, list removed or gone from the store, oversized list split, invalid list ignored.
@MainActor
struct BlocklistLoaderTests {
    private let store = FakeRuleListStore()
    private let date = Date(timeIntervalSince1970: 2_000_000)

    private static func rules(_ count: Int, filter: String = "pub") -> Data {
        let rule = #"{"trigger":{"url-filter":"\#(filter)"},"action":{"type":"block"}}"#
        return Data(("[" + Array(repeating: rule, count: count).joined(separator: ",") + "]").utf8)
    }

    private static func entry(_ identifier: String, version: String = "1") -> BlocklistEntry {
        BlocklistEntry(identifier: identifier, name: identifier, version: version, file: "\(identifier).json")
    }

    private func loader(rules: [String: Data] = [:]) -> BlocklistLoader<FakeRuleListStore> {
        var loader = BlocklistLoader(store: store) { entry in
            guard let data = rules[entry.identifier] else {
                throw BlocklistBundle.Error.missingFile(entry.file)
            }
            return data
        }
        loader.now = { [date] in date }
        loader.minimumPartSize = 1
        return loader
    }

    @Test func `the first launch compiles every list`() async {
        let loaded = await loader(rules: ["a": Self.rules(2), "b": Self.rules(3)]).load([Self.entry("a"), Self.entry("b")], previous: [])
        #expect(loaded.map(\.entry.identifier) == ["a", "b"])
        #expect(loaded.map(\.wasCompiled) == [true, true])
        #expect(loaded.map(\.record.ruleCount) == [2, 3])
        #expect(loaded.map(\.record.compiledAt) == [date, date])
        #expect(store.compiled == ["matcha-blocklist.a.1", "matcha-blocklist.b.1"])
        #expect(loaded.map(\.ruleLists.count) == [1, 1])
    }

    @Test func `the same version is reused without compiling`() async {
        let entries = [Self.entry("a")]
        let first = await loader(rules: ["a": Self.rules(2)]).load(entries, previous: [])
        let second = await loader(rules: [:]).load(entries, previous: first.map(\.record))
        #expect(second.map(\.wasCompiled) == [false])
        #expect(second.map(\.record) == first.map(\.record))
        #expect(second.first?.ruleLists == first.first?.ruleLists)
        #expect(store.compiled == ["matcha-blocklist.a.1"])
        #expect(store.removed.isEmpty)
    }

    @Test func `a new version is compiled and the old one removed`() async {
        let first = await loader(rules: ["a": Self.rules(2)]).load([Self.entry("a")], previous: [])
        let second = await loader(rules: ["a": Self.rules(4)]).load([Self.entry("a", version: "2")], previous: first.map(\.record))
        #expect(second.map(\.wasCompiled) == [true])
        #expect(second.first?.record.ruleCount == 4)
        #expect(store.removed == ["matcha-blocklist.a.1"])
        #expect(await store.identifiers() == ["matcha-blocklist.a.2"])
    }

    @Test func `a list gone from the store is compiled again`() async {
        let record = CompiledBlocklist(
            identifier: "a",
            version: "1",
            storeIdentifiers: ["matcha-blocklist.a.1"],
            ruleCount: 2,
            compiledAt: .distantPast,
        )
        let loaded = await loader(rules: ["a": Self.rules(2)]).load([Self.entry("a")], previous: [record])
        #expect(loaded.map(\.wasCompiled) == [true])
        #expect(loaded.first?.record.compiledAt == date)
    }

    @Test func `a list removed from the app leaves the store, other identifiers stay`() async {
        let store = FakeRuleListStore(lists: ["matcha-blocklist.retiree.3": "[]", "extension.ublock": "[]"])
        let loader = BlocklistLoader(store: store) { _ in Self.rules(1) }
        let loaded = await loader.load([], previous: [])
        #expect(loaded.isEmpty)
        #expect(store.removed == ["matcha-blocklist.retiree.3"])
        #expect(await store.identifiers() == ["extension.ublock"])
    }

    @Test func `a list over the maximum is split before compiling`() async {
        var loader = loader(rules: ["a": Self.rules(5)])
        loader.maximumRuleCount = 2
        let loaded = await loader.load([Self.entry("a")], previous: [])
        #expect(store.compiled == ["matcha-blocklist.a.1.part-1", "matcha-blocklist.a.1.part-2", "matcha-blocklist.a.1.part-3"])
        #expect(loaded.first?.record.ruleCount == 5)
        #expect(loaded.first?.record.storeIdentifiers == store.compiled)
        #expect(loaded.first?.ruleLists.count == 3)
    }

    /// WebKit rejects the whole list, then parts of 5: the list ends up in parts of 3 (halves rounded up).
    @Test func `a list refused as too big is split in halves until it compiles`() async {
        store.maximumRuleCount = 3
        let loaded = await loader(rules: ["a": Self.rules(10)]).load([Self.entry("a")], previous: [])
        #expect(loaded.first?.record.storeIdentifiers == (1 ... 4).map { "matcha-blocklist.a.1.part-\($0)" })
        #expect(loaded.first?.record.ruleCount == 10)
        #expect(store.compiled.first == "matcha-blocklist.a.1")
        // Nothing from the rejected attempts remains in the store.
        #expect(await store.identifiers() == (1 ... 4).map { "matcha-blocklist.a.1.part-\($0)" })
    }

    @Test func `splitting stops at the minimum part size`() async {
        store.maximumRuleCount = 0
        var loader = loader(rules: ["a": Self.rules(4)])
        loader.minimumPartSize = 2
        #expect(await loader.load([Self.entry("a")], previous: []).isEmpty)
    }

    @Test func `an invalid or missing list is skipped, the others load`() async {
        let rules = ["a": Self.rules(1, filter: "invalide"), "c": Self.rules(1)]
        let loaded = await loader(rules: rules).load([Self.entry("a"), Self.entry("b"), Self.entry("c")], previous: [])
        #expect(loaded.map(\.entry.identifier) == ["c"])
        #expect(await store.identifiers() == ["matcha-blocklist.c.1"])
    }

    @Test func `too many rules is told apart from other compile errors`() {
        let tooMany = NSError(
            domain: WKError.errorDomain,
            code: WKError.Code.contentRuleListStoreCompileFailed.rawValue,
            userInfo: [NSHelpAnchorErrorKey: "Rule list compilation failed: Too many rules in JSON array."],
        )
        let invalid = NSError(
            domain: WKError.errorDomain,
            code: WKError.Code.contentRuleListStoreCompileFailed.rawValue,
            userInfo: [NSHelpAnchorErrorKey: "Rule list compilation failed: Invalid url-filter object."],
        )
        let otherDomain = NSError(domain: NSCocoaErrorDomain, code: 6, userInfo: [NSHelpAnchorErrorKey: "Too many rules"])
        #expect(ContentRuleListError.isTooManyRules(tooMany))
        #expect(!ContentRuleListError.isTooManyRules(invalid))
        #expect(!ContentRuleListError.isTooManyRules(otherDomain))
        #expect(ContentRuleListError.message(of: invalid) == "Rule list compilation failed: Invalid url-filter object.")
    }
}
