import Foundation

/// Command bar text in the forms the ranking compares, with its reading (address or search) by
/// `AddressResolver`.
nonisolated struct CommandQuery: Equatable, Sendable {
    /// Text as entered.
    let text: String
    /// Text without surrounding whitespace: the one that is opened or searched.
    let trimmed: String
    /// Folded text (`CommandText.fold`).
    let folded: String
    /// Words of the folded text, separated by spaces.
    let tokens: [String]
    /// What must start a word for each typed word: its pieces if it is split by punctuation
    /// (“node.js” → “node”, “js”), otherwise the whole word (“c++” stays “c++”).
    let wordParts: [[String]]
    /// Folded text without spaces, for fuzzy matching.
    let compact: String
    /// Folded text without “https://”, “http://”, “www.” or trailing “/”, compared with addresses.
    let urlFolded: String
    let searchEngine: SearchEngine
    /// Nil for an empty text.
    let interpretation: AddressInterpretation?
    /// Key (`CommandText.urlKey`) of the typed address; nil for a search.
    let addressKey: String?

    init(text: String, searchEngine: SearchEngine) {
        self.text = text
        trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        folded = CommandText.fold(text)
        tokens = folded.split(separator: " ").map(String.init)
        wordParts = tokens.map { token in
            let pieces = CommandText.words(token)
            return pieces.count > 1 ? pieces.map(String.init) : [token]
        }
        compact = tokens.joined()
        let stripped = CommandText.stripURLPrefixes(folded)
        urlFolded = stripped.count > 1 && stripped.hasSuffix("/") ? String(stripped.dropLast()) : stripped
        self.searchEngine = searchEngine
        let interpretation = AddressResolver(searchEngine: searchEngine).interpret(trimmed)
        self.interpretation = interpretation
        addressKey = if case let .address(url) = interpretation {
            CommandText.urlKey(url)
        } else {
            nil
        }
    }

    var isEmpty: Bool {
        trimmed.isEmpty
    }

    /// True if the text is read as a search (and not as an address).
    var isSearch: Bool {
        if case .search = interpretation {
            return true
        }
        return false
    }

    /// Domain name typed alone (“apple.com”, “node.js”): read as an `https` address, without scheme, port, path,
    /// query, fragment or “@”.
    var isBareDomain: Bool {
        guard case let .address(url) = interpretation, url.scheme == "https" else {
            return false
        }
        return !trimmed.contains { ":/?#@".contains($0) }
    }
}
