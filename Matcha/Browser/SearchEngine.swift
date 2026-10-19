import Foundation

/// Search engine used when the typed text is not an address.
nonisolated enum SearchEngine: String, CaseIterable, Sendable {
    case google
    case duckDuckGo
    case bing

    /// Engine used as long as the user has not chosen another one.
    static let defaultEngine = SearchEngine.google

    /// Name displayed in the settings.
    var name: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        }
    }

    /// Search URL for `query`, fully encoded.
    func searchURL(for query: String) -> URL? {
        Self.url(base: searchBaseURL, query: query)
    }

    /// URL of the search suggestions for `query` (OpenSearch format: `["text", ["suggestion", …]]`),
    /// fully encoded.
    func suggestionsURL(for query: String) -> URL? {
        Self.url(base: suggestionsBaseURL, query: query)
    }

    private var searchBaseURL: String {
        switch self {
        case .google: "https://www.google.com/search?q="
        case .duckDuckGo: "https://duckduckgo.com/?q="
        case .bing: "https://www.bing.com/search?q="
        }
    }

    /// Undocumented addresses, the ones Firefox uses (checked on 2026-10-17).
    private var suggestionsBaseURL: String {
        switch self {
        case .google: "https://www.google.com/complete/search?client=firefox&ie=utf-8&oe=utf-8&q="
        case .duckDuckGo: "https://duckduckgo.com/ac/?type=list&q="
        case .bing: "https://www.bing.com/osjson.aspx?query="
        }
    }

    private static func url(base: String, query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) else {
            return nil
        }
        return URL(string: base + encoded)
    }

    /// Unreserved characters of RFC 3986. Everything else is encoded, including `+`, `&`, `#`
    /// and accented letters (which `CharacterSet.alphanumerics` would let through).
    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
    )
}
