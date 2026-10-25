import Foundation
@testable import Matcha
import Testing

/// Requests sent by the suggestions client.
private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

struct SearchSuggestionClientTests {
    private func client(
        status: Int = 200,
        body: Data = Data(#"["pain",["pain perdu","pain au levain"]]"#.utf8),
        recorder: RequestRecorder = RequestRecorder(),
    ) -> SearchSuggestionClient {
        SearchSuggestionClient { request in
            await recorder.record(request)
            let response = required(HTTPURLResponse(
                url: required(request.url, else: testURL("https://suggestions.test/")),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json; charset=utf-8"],
            ), else: HTTPURLResponse())
            return (body, response)
        }
    }

    @Test func `configuration keeps no cookies cache or credentials`() {
        let configuration = SearchSuggestionClient.makeConfiguration()
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForRequest == 2)
        #expect(configuration.timeoutIntervalForResource == 4)
        #expect(!configuration.waitsForConnectivity)
    }

    @Test func `request asks for json at the engine url without cookies`() async throws {
        let recorder = RequestRecorder()
        _ = try await client(recorder: recorder).suggestions(for: "pain au", engine: .duckDuckGo)
        let requests = await recorder.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://duckduckgo.com/ac/?type=list&q=pain%20au")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(!request.httpShouldHandleCookies)
        #expect(request.timeoutInterval == 2)
        #expect(request.attribution == .user)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func `non 2xx status throws`() async {
        await #expect(throws: SearchSuggestionError.status(503)) {
            try await client(status: 503).suggestions(for: "pain", engine: .google)
        }
    }

    @Test func `oversized body throws`() async {
        let body = Data(count: SearchSuggestionClient.maximumSize + 1)
        await #expect(throws: SearchSuggestionError.tooLarge) {
            try await client(body: body).suggestions(for: "pain", engine: .bing)
        }
    }

    @Test func `ok response returns parsed suggestions`() async throws {
        let suggestions = try await client().suggestions(for: "pain", engine: .google)
        #expect(suggestions == ["pain perdu", "pain au levain"])
    }
}
