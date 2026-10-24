import Foundation

/// Answer of the fake server.
struct MockResponse {
    var status: Int
    var headers: [String: String] = [:]
    var body = Data()
}

/// Fake HTTP server for the tests: each test registers a handler for its own host, called for every request.
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest, Data) throws -> MockResponse

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [String: Handler] = [:]

    /// A host of its own, served by `handler`, and a session that goes through it.
    static func serve(_ handler: @escaping Handler) -> (host: String, session: URLSession) {
        let host = "test-\(UUID().uuidString.lowercased()).example"
        lock.withLock { handlers[host] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return (host, URLSession(configuration: configuration))
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handlers[request.url?.host ?? ""] }
        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        do {
            let answer = try handler(request, Self.body(of: request))
            let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: answer.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Body of the request: moved to a stream by `URLSession`.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    /// JSON answer.
    static func json(_ status: Int, _ object: Any, headers: [String: String] = [:]) throws -> MockResponse {
        try MockResponse(
            status: status,
            headers: headers.merging(["Content-Type": "application/json"]) { mine, _ in mine },
            body: JSONSerialization.data(withJSONObject: object),
        )
    }

    /// Problem answer (`application/problem+json`).
    static func problem(_ status: Int, _ code: String, headers: [String: String] = [:]) -> MockResponse {
        MockResponse(
            status: status,
            headers: headers.merging(["Content-Type": "application/problem+json"]) { mine, _ in mine },
            body: Data(#"{"status":\#(status),"code":"\#(code)","title":"\#(code)"}"#.utf8),
        )
    }
}
