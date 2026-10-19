import Foundation
@testable import Matcha
import Testing

/// Splitting a rule list too big for WebKit (task 6.2): parts in order, a short list left intact.
struct RuleListSplitterTests {
    /// Rule numbered `index`, to follow the order.
    private static func rule(_ index: Int) -> String {
        #"{"trigger":{"url-filter":"^https?://r\#(index)\\.example/"},"action":{"type":"block"}}"#
    }

    private static func list(_ count: Int) -> Data {
        Data(("[" + (0 ..< count).map(rule).joined(separator: ",") + "]").utf8)
    }

    /// Filters of the rules of `part`, in order.
    private static func filters(of part: String) throws -> [String] {
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(part.utf8)) as? [[String: [String: String]]])
        return rules.compactMap { $0["trigger"]?["url-filter"] }
    }

    @Test func `a short list stays whole and unchanged`() throws {
        let data = Self.list(3)
        let result = try RuleListSplitter.parts(of: data, maximumRuleCount: 3)
        #expect(result.ruleCount == 3)
        #expect(result.parts == [String(bytes: data, encoding: .utf8)])
    }

    @Test func `a long list is cut in order into parts of at most the maximum`() throws {
        let result = try RuleListSplitter.parts(of: Self.list(7), maximumRuleCount: 3)
        #expect(result.ruleCount == 7)
        let parts = try result.parts.map(Self.filters(of:))
        #expect(parts.map(\.count) == [3, 3, 1])
        let expected = (0 ..< 7).map { "^https?://r\($0)\\.example/" }
        #expect(parts.flatMap(\.self) == expected)
    }

    /// Slashes in the expressions are not escaped (“\/”): the parts stay readable and light.
    @Test func `parts keep slashes unescaped`() throws {
        let result = try RuleListSplitter.parts(of: Self.list(2), maximumRuleCount: 1)
        #expect(result.parts.allSatisfy { !$0.contains(#"\/"#) && $0.contains("://") })
    }

    @Test func `an empty list is one empty part`() throws {
        let result = try RuleListSplitter.parts(of: Data("[]".utf8), maximumRuleCount: 3)
        #expect(result.ruleCount == 0)
        #expect(result.parts == ["[]"])
    }

    @Test func `a maximum below one is treated as one`() throws {
        let result = try RuleListSplitter.parts(of: Self.list(2), maximumRuleCount: 0)
        #expect(result.parts.count == 2)
    }

    @Test func `a non array or unreadable json is refused`() {
        #expect(throws: RuleListSplitter.Error.notAnArray) {
            try RuleListSplitter.parts(of: Data(#"{"rules":[]}"#.utf8), maximumRuleCount: 3)
        }
        #expect(throws: (any Error).self) {
            try RuleListSplitter.parts(of: Data("[{".utf8), maximumRuleCount: 3)
        }
    }

    @Test func `splits off the main thread too`() async throws {
        let result = try await RuleListSplitter.partsInBackground(of: Self.list(5), maximumRuleCount: 2)
        #expect(result.parts.count == 3)
    }
}
