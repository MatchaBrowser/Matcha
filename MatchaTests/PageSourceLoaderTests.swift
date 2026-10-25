import Foundation
@testable import Matcha
import Testing

/// The network path of “View Page Source” (review TS12): the profile's cookies and the browser's user agent, the
/// response's encoding, the limit. Against a fake server.
struct PageSourceLoaderTests {
    /// Last request received by a fake server's handler.
    private final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: URLRequest?

        var request: URLRequest? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private func cookie(for host: String) throws -> HTTPCookie {
        try #require(HTTPCookie(properties: [.domain: host, .path: "/", .name: "session", .value: "abc"]))
    }

    /// The loader's configuration, its requests answered by `handler`.
    private func serve(_ handler: @escaping MockURLProtocol.Handler) throws -> (URL, URLSessionConfiguration) {
        let (host, _) = MockURLProtocol.serve(handler)
        let configuration = try PageSourceLoader.makeConfiguration(cookies: [cookie(for: host)], userAgent: "Matcha Test")
        configuration.protocolClasses = [MockURLProtocol.self]
        return (testURL("https://\(host)/page"), configuration)
    }

    @Test func `the session holds the profile's cookies and presents itself as the browser`() throws {
        let configuration = try PageSourceLoader.makeConfiguration(cookies: [cookie(for: "example.test")], userAgent: "Matcha Test")
        #expect(configuration.httpCookieStorage?.cookies?.map(\.name) == ["session"])
        #expect(configuration.httpAdditionalHeaders?["User-Agent"] as? String == "Matcha Test")
        #expect(configuration.timeoutIntervalForResource == PageSourceLoader.timeout)
    }

    @Test func `the response comes with its encoding`() async throws {
        let received = Received()
        let (page, configuration) = try serve { request, _ in
            received.request = request
            // “<p>café</p>” in Latin-1.
            let body = Data("<p>caf".utf8) + Data([0xE9]) + Data("</p>".utf8)
            return MockResponse(status: 200, headers: ["Content-Type": "text/html; charset=iso-8859-1"], body: body)
        }
        let (data, encoding) = try await PageSourceLoader.download(page, configuration: configuration)
        #expect(encoding == "iso-8859-1")
        #expect(PageSource.text(of: data, textEncodingName: encoding) == "<p>café</p>")
        #expect(received.request?.value(forHTTPHeaderField: "User-Agent") == "Matcha Test")
    }

    @Test func `a response announced past the limit is not read`() async throws {
        let (page, configuration) = try serve { _, _ in
            MockResponse(status: 200, headers: ["Content-Length": String(PageSourceLoader.maximumSize + 1)], body: Data("<p>".utf8))
        }
        await #expect(throws: PageSourceLoader.Failure.tooLarge) {
            _ = try await PageSourceLoader.download(page, configuration: configuration)
        }
    }
}
