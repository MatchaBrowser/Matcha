import Foundation
import OSLog

/// HTTP client of a sync server's API v1 (`SYNC.md` § 4): JSON bodies, header `Matcha-Client` on every request,
/// bearer token on the authenticated routes, renewed once (`SyncTokenStore`) when the server answers
/// `token_expired`. An error answer becomes a `SyncServerError` with its stable code. Certificates: only those macOS
/// trusts (default checks of `URLSession`), without exception.
final nonisolated class SyncAPIClient: Sendable {
    let address: SyncServerAddress
    let base: URL
    let session: URLSession
    /// “1.2.0 (128)”.
    let clientVersion: String
    /// Tokens of the session; nil before signing in.
    let tokens: SyncTokenStore?
    let clock = SyncServerClock()

    init(address: SyncServerAddress, session: URLSession, clientVersion: String, tokens: SyncTokenStore? = nil) throws {
        guard let base = address.apiBase else {
            throw SyncClientError.notASyncServer
        }
        self.address = address
        self.base = base
        self.session = session
        self.clientVersion = clientVersion
        self.tokens = tokens
    }

    /// Ephemeral session: no cookie, no cache.
    static func makeSession(timeout: TimeInterval = 30) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// The same client signed in with `tokens`.
    func signedIn(with tokens: SyncTokenStore) throws -> SyncAPIClient {
        try SyncAPIClient(address: address, session: session, clientVersion: clientVersion, tokens: tokens)
    }

    // MARK: Requests

    /// Request to `path` (relative to `…/v1`), with a JSON or binary body.
    func urlRequest(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
    ) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        var request = URLRequest(url: components?.url ?? base.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(clientVersion, forHTTPHeaderField: "Matcha-Client")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Sends `request`; on an authenticated route, with the access token, renewed once if it expired. `limit`: largest
    /// body accepted (a package, an avatar), read as it comes (review TR2); nil for the JSON answers.
    func send(_ request: URLRequest, authenticated: Bool, limit: Int? = nil) async throws -> (Data, HTTPURLResponse) {
        guard authenticated else {
            return try await perform(request, limit: limit)
        }
        guard let tokens else {
            throw SyncClientError.signedOut
        }
        let token = await tokens.accessToken
        do {
            return try await perform(request, token: token, limit: limit)
        } catch let error as SyncServerError where error.code == SyncServerError.tokenExpired {
            let renewed = try await tokens.renewed(after: token) { [self] refreshToken in
                try await renew(refreshToken)
            }
            return try await perform(request, token: renewed, limit: limit)
        }
    }

    private func perform(_ request: URLRequest, token: String? = nil, limit: Int? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await body(of: request, limit: limit)
        guard let http = response as? HTTPURLResponse else {
            throw SyncClientError.unreadableAnswer
        }
        await clock.record(http.value(forHTTPHeaderField: "Date"))
        guard (200 ..< 300).contains(http.statusCode) else {
            throw Self.error(from: data, response: http)
        }
        return (data, http)
    }

    /// The answer to `request`; with a `limit`, an error answer is read from its first bytes only, and a larger
    /// body is refused without being read to its end.
    private func body(of request: URLRequest, limit: Int?) async throws -> (Data, URLResponse) {
        guard let limit else {
            return try await session.data(for: request)
        }
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            return try await (BoundedRead.prefix(of: bytes, limit: SyncEventStream.maximumLineLength), response)
        }
        do {
            return try await (BoundedRead.data(of: bytes, expectedLength: response.expectedContentLength, limit: limit), response)
        } catch is BoundedRead.TooLarge {
            throw SyncClientError.unreadableAnswer
        }
    }

    /// `SyncServerError` read from an error answer.
    static func error(from data: Data, response: HTTPURLResponse) -> SyncServerError {
        let problem = try? JSONDecoder().decode(SyncProblem.self, from: data)
        let retryAfter = SyncRetryAfter.seconds(from: response.value(forHTTPHeaderField: "Retry-After"))
        let fallback = response.statusCode >= 500 ? SyncServerError.serverError : SyncServerError.invalidRequest
        return SyncServerError(status: response.statusCode, code: problem?.code ?? fallback, retryAfter: retryAfter)
    }

    /// JSON route: `body` encoded, the answer decoded as `Response`.
    func json<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        headers: [String: String] = [:],
        authenticated: Bool,
    ) async throws -> Response {
        let data = try await call(method, path, query: query, body: body, headers: headers, authenticated: authenticated)
        do {
            return try SyncCoding.decoder().decode(Response.self, from: data)
        } catch {
            throw SyncClientError.unreadableAnswer
        }
    }

    /// Route without an expected answer body (`204`).
    @discardableResult
    func call(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        headers: [String: String] = [:],
        authenticated: Bool,
    ) async throws -> Data {
        let encoded = try body.map { try SyncCoding.encoder().encode($0) }
        var request = urlRequest(method, path, query: query, body: encoded)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return try await send(request, authenticated: authenticated).0
    }

    /// `POST /v1/auth/refresh`, without the access token.
    func renew(_ refreshToken: String) async throws -> SyncRefreshResponse {
        try await json("POST", "auth/refresh", body: SyncRefreshRequest(refreshToken: refreshToken), authenticated: false)
    }
}
