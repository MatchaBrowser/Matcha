import Foundation

/// Failure of a suggestion request, logged without the searched text.
nonisolated enum SearchSuggestionError: Error, Equatable {
    /// HTTP response outside 2xx.
    case status(Int)
    /// Response of more than `SearchSuggestionClient.maximumSize` bytes.
    case tooLarge
    /// Response that does not have the OpenSearch shape.
    case malformed
}

/// Suggestion request to the search engine, without cookies, cache or credentials.
nonisolated struct SearchSuggestionClient: Sendable {
    typealias Load = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = SearchSuggestionClient()
    /// Maximum accepted size of a response, in bytes.
    static let maximumSize = 65536

    private let load: Load

    /// `load` nil: a URLSession from `makeConfiguration()` (tests: fake response).
    init(load: Load? = nil) {
        if let load {
            self.load = load
        } else {
            let session = URLSession(configuration: Self.makeConfiguration())
            self.load = { request in try await session.data(for: request) }
        }
    }

    /// Ephemeral session: no cookies (Google and Bing set some), no cache, no credentials; short timeouts, without
    /// waiting for connectivity.
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

    /// Engine suggestions for `query`. Cancelling the Swift task cancels the request.
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
