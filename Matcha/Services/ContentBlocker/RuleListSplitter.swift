import Foundation

/// Splits a rule list in WebKit's content blocking format (a JSON array) into parts of at most `maximumRuleCount`
/// rules, in order (task 6.2): WebKit refuses to compile a list that is too big. Each part becomes a separate list in
/// the store; an `ignore-previous-rules` rule only acts within its own part (as within its list, `DECISIONS.md`).
nonisolated enum RuleListSplitter {
    /// Number of rules beyond which WebKit refuses a list (“Too many rules in JSON array.”, checked on macOS 27:
    /// 150,000 rules pass, 150,001 do not).
    static let webKitMaximumRuleCount = 150_000

    enum Error: Swift.Error, Equatable {
        /// The JSON is not an array of rules.
        case notAnArray
        /// A part cannot be read back as UTF-8 (does not happen: `JSONSerialization` writes UTF-8).
        case notUTF8
    }

    /// Number of rules in the list, and its parts (JSON); a small enough list stays as is, in one part.
    struct Parts: Equatable, Sendable {
        let ruleCount: Int
        let parts: [String]
    }

    /// Splits `rules` (JSON); throws if the JSON is unreadable or is not an array.
    static func parts(of rules: Data, maximumRuleCount: Int) throws -> Parts {
        guard let array = try JSONSerialization.jsonObject(with: rules) as? [Any] else {
            throw Error.notAnArray
        }
        let size = max(1, maximumRuleCount)
        // Small enough and in UTF-8: as is, without rewriting it.
        if array.count <= size, let text = String(bytes: rules, encoding: .utf8) {
            return Parts(ruleCount: array.count, parts: [text])
        }
        var parts: [String] = []
        for start in stride(from: 0, to: max(array.count, 1), by: size) {
            try parts.append(json(of: Array(array[start ..< min(start + size, array.count)])))
        }
        return Parts(ruleCount: array.count, parts: parts)
    }

    private static func json(of rules: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: rules, options: [.withoutEscapingSlashes])
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw Error.notUTF8
        }
        return text
    }

    /// Same split, off the main thread (a big list takes a few tenths of a second to read).
    @concurrent
    static func partsInBackground(of rules: Data, maximumRuleCount: Int) async throws -> Parts {
        try parts(of: rules, maximumRuleCount: maximumRuleCount)
    }
}
