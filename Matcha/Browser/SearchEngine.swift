import Foundation

/// Moteur de recherche utilisé quand le texte saisi n'est pas une adresse.
nonisolated enum SearchEngine: String, CaseIterable, Sendable {
    case google
    case duckDuckGo
    case bing

    /// Moteur utilisé tant que l'utilisateur n'en a pas choisi d'autre.
    static let defaultEngine = SearchEngine.google

    /// Nom affiché dans les réglages.
    var name: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        }
    }

    /// URL de recherche de `query`, encodée en entier.
    func searchURL(for query: String) -> URL? {
        Self.url(base: searchBaseURL, query: query)
    }

    /// URL des suggestions de recherche de `query` (format OpenSearch : `["texte", ["suggestion", …]]`),
    /// encodée en entier.
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

    /// Adresses non documentées, celles qu'utilise Firefox (vérifiées le 2026-10-17).
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

    /// Caractères non réservés de la RFC 3986. Tout le reste est encodé, y compris `+`, `&`, `#`
    /// et les lettres accentuées (que `CharacterSet.alphanumerics` laisserait passer).
    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
    )
}
