import Foundation

/// Refuses every `http` and `https` request of the session it is given to: in the unit tests' host app, the icons of
/// the simulated pages are never downloaded from the real websites (review TS4). `data:` and the other schemes go on.
final nonisolated class OfflineURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
