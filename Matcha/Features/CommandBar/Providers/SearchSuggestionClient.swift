import Foundation

/// Échec d'une demande de suggestions, journalisé sans le texte cherché.
nonisolated enum SearchSuggestionError: Error, Equatable {
    /// Réponse HTTP hors 2xx.
    case status(Int)
    /// Réponse de plus de `SearchSuggestionClient.maximumSize` octets.
    case tooLarge
    /// Réponse qui n'a pas la forme OpenSearch.
    case malformed
}

/// Demande de suggestions au moteur de recherche, sans cookies, cache ni identifiants.
nonisolated struct SearchSuggestionClient: Sendable {
    typealias Load = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = SearchSuggestionClient()
    /// Taille maximale acceptée d'une réponse, en octets.
    static let maximumSize = 65536

    private let load: Load

    /// `load` nil : une URLSession de `makeConfiguration()` (tests : réponse factice).
    init(load: Load? = nil) {
        if let load {
            self.load = load
        } else {
            let session = URLSession(configuration: Self.makeConfiguration())
            self.load = { request in try await session.data(for: request) }
        }
    }

    /// Session éphémère : ni cookies (Google et Bing en posent), ni cache, ni identifiants ; délais
    /// courts, sans attendre le réseau.
    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        return configuration
    }

    static func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpShouldHandleCookies = false
        request.attribution = .user
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Suggestions du moteur pour `query`. Annuler la tâche Swift annule la requête.
    func suggestions(for query: String, engine: SearchEngine) async throws -> [String] {
        guard let url = engine.suggestionsURL(for: query) else {
            return []
        }
        let (data, response) = try await load(Self.makeRequest(for: url))
        if let response = response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
            throw SearchSuggestionError.status(response.statusCode)
        }
        guard data.count <= Self.maximumSize else {
            throw SearchSuggestionError.tooLarge
        }
        return try SearchSuggestionParser.parse(data, textEncodingName: response.textEncodingName)
    }
}
