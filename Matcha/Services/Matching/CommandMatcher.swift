import Foundation

/// Match tier between the typed text and a result, from loosest to strictest.
nonisolated enum MatchTier: Int, Comparable, Sendable {
    case fuzzy = 1
    case substring
    case wordPrefix
    case prefix
    case exact

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Fields of a result compared with the typed text, folded once and for all: titles, readable address and address
/// key. History (task 5.5) prepares them when it loads rather than on each keystroke.
nonisolated struct CommandMatchFields: Equatable, Sendable {
    /// Folded titles.
    let titles: [String]
    /// Folded readable address.
    let address: String?
    /// Key of the address (`CommandText.urlKey`).
    let urlKey: String?

    init(titles: [String], url: URL?) {
        self.titles = titles.map(CommandText.fold)
        address = url.map { CommandText.fold(CommandText.displayURL($0)) }
        urlKey = url.map(CommandText.urlKey)
    }

    /// Same page as the typed address (`CommandText.urlKey`): an address pasted as is
    /// (“https://www.apple.com/”, fragment, “%20”) designates the tab open on it.
    func isSamePage(as typedKey: String?) -> Bool {
        typedKey != nil && urlKey == typedKey
    }
}

/// Match found by `CommandMatcher`.
nonisolated struct CommandMatch: Equatable, Sendable {
    let tier: MatchTier
    /// 100 outside the fuzzy tier; otherwise the compactness of the letters found (`fuzzyQuality`).
    let quality: Int

    /// Quality band of a fuzzy match (3: ≥ 75, 2: ≥ 50, 1: below); 0 for the other tiers.
    var fuzzyBucket: Int {
        guard tier == .fuzzy else {
            return 0
        }
        switch quality {
        case 75...: return 3
        case 50...: return 2
        default: return 1
        }
    }
}

/// Match of the typed text against the titles and address of a result. Tiers, from strictest to loosest (the first
/// reached wins): exact (a title, the readable address or the same page), prefix of a title or of the address, word
/// start for each typed word, substring (2 characters at least), then fuzzy (3 to 32 characters, letters in order
/// from a word start, quality of at least 30). Folded texts (`CommandText.fold`), addresses without scheme or “www.”.
nonisolated enum CommandMatcher {
    /// Below this, a fuzzy match is too scattered to be offered.
    static let minimumFuzzyQuality = 30
    /// Beyond this, the text is no longer searched fuzzily.
    static let maximumFuzzyLength = 32
    /// Length read in each field for fuzzy matching.
    static let fuzzyFieldLength = 200

    /// Best tier reached by `query` on `titles` and `url`, or nil if there is none or if it is below
    /// `minimumTier`.
    static func match(_ query: CommandQuery, titles: [String], url: URL?, minimumTier: MatchTier = .fuzzy) -> CommandMatch? {
        match(query, fields: CommandMatchFields(titles: titles, url: url), minimumTier: minimumTier)
    }

    /// Like `match(_:titles:url:minimumTier:)`, with fields already folded (history, task 5.5).
    static func match(_ query: CommandQuery, fields: CommandMatchFields, minimumTier: MatchTier = .fuzzy) -> CommandMatch? {
        guard !query.folded.isEmpty else {
            return nil
        }
        if let tier = strictTier(query, fields) {
            return tier >= minimumTier ? CommandMatch(tier: tier, quality: 100) : nil
        }
        guard minimumTier == .fuzzy, let quality = bestFuzzyQuality(query.compact, fields), quality >= minimumFuzzyQuality else {
            return nil
        }
        return CommandMatch(tier: .fuzzy, quality: quality)
    }

    /// Compactness (0 to 100) of the letters of `needle` found in order in `haystack`, the first at the start of a
    /// word: length of `needle` over the length of the shortest window found by advancing as early as possible. Nil
    /// if no word start allows finding everything.
    static func fuzzyQuality(of needle: String, in haystack: String) -> Int? {
        let needle = Array(needle)
        let haystack = Array(haystack)
        guard let first = needle.first else {
            return nil
        }
        var best: Int?
        for start in haystack.indices where haystack[start] == first && startsWord(haystack, at: start) {
            // If the letters are missing from this start, they are also missing from the following ones.
            guard let end = greedyEnd(of: needle, in: haystack, from: start) else {
                break
            }
            let quality = Int((Double(needle.count) / Double(end - start + 1) * 100).rounded(.down))
            best = max(best ?? 0, quality)
        }
        return best
    }

    // MARK: Tiers

    private static func strictTier(_ query: CommandQuery, _ fields: CommandMatchFields) -> MatchTier? {
        let folded = query.folded
        let urlFolded = query.urlFolded
        let address = urlFolded.isEmpty ? nil : fields.address
        if fields.titles.contains(folded) || address == urlFolded || fields.isSamePage(as: query.addressKey) {
            return .exact
        }
        if fields.titles.contains(where: { $0.hasPrefix(folded) }) || address?.hasPrefix(urlFolded) == true {
            return .prefix
        }
        if isWordPrefixMatch(query, fields) {
            return .wordPrefix
        }
        if folded.count >= 2, fields.titles.contains(where: { $0.contains(folded) }) || address?.contains(urlFolded) == true {
            return .substring
        }
        return nil
    }

    /// Each typed word starts a word of the titles or of the address, in any order. A typed word split by
    /// punctuation (“node.js”, “6.4”) counts as its pieces; “c++”, a single piece, stays whole so as not to be
    /// reduced to “c” (and therefore starts no word).
    private static func isWordPrefixMatch(_ query: CommandQuery, _ fields: CommandMatchFields) -> Bool {
        let haystacks = fields.titles + [fields.address].compactMap(\.self)
        return !query.wordParts.isEmpty && query.wordParts.allSatisfy { parts in
            parts.allSatisfy { part in haystacks.contains { hasWord(startingWith: part, in: $0) } }
        }
    }

    /// True if a word of `text` (run of letters and digits, like `CommandText.words`) starts with `part`, without
    /// splitting the text: history (task 5.5) passes thousands of addresses on each keystroke.
    private static func hasWord(startingWith part: String, in text: String) -> Bool {
        guard let first = part.first, part.allSatisfy(isWordCharacter) else {
            return false
        }
        var previousIsWordCharacter = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isWord = isWordCharacter(character)
            if isWord, !previousIsWordCharacter, character == first, text[index...].hasPrefix(part) {
                return true
            }
            previousIsWordCharacter = isWord
            index = text.index(after: index)
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func bestFuzzyQuality(_ compact: String, _ fields: CommandMatchFields) -> Int? {
        guard (3 ... maximumFuzzyLength).contains(compact.count) else {
            return nil
        }
        let haystacks = (fields.titles + [fields.address].compactMap(\.self)).map { String($0.prefix(fuzzyFieldLength)) }
        return haystacks.compactMap { fuzzyQuality(of: compact, in: $0) }.max()
    }

    // MARK: Fuzzy

    private static func startsWord(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else {
            return true
        }
        let previous = characters[index - 1]
        return !previous.isLetter && !previous.isNumber
    }

    /// Index of the last letter of `needle` found by advancing as early as possible from `start` (where its first
    /// letter is), nil if one is missing.
    private static func greedyEnd(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        var position = start
        for character in needle.dropFirst() {
            guard let found = haystack[(position + 1)...].firstIndex(of: character) else {
                return nil
            }
            position = found
        }
        return position
    }
}
