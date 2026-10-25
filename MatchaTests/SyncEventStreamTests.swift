import Foundation
@testable import Matcha
import Testing

/// The server's event stream (`SYNC.md` § 4.6, review TS8): lines read, waits before reconnecting, and the stream
/// against a fake server.
@MainActor
struct SyncEventStreamTests {
    /// Requests received by a fake server's handler.
    private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []

        /// Records the request (`path` and token) and returns its rank, from 1.
        func record(_ request: URLRequest) -> Int {
            let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
            return lock.withLock {
                list.append([request.url?.path ?? "", token].compactMap(\.self).joined(separator: " "))
                return list.count
            }
        }

        var all: [String] {
            lock.withLock { list }
        }
    }

    private nonisolated static func events(_ text: String) -> MockResponse {
        MockResponse(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(text.utf8))
    }

    /// A stream of `handler`'s server, its access token `old`, with what it reports.
    private func stream(_ handler: @escaping MockURLProtocol.Handler) throws -> SyncEventStream {
        let (host, session) = MockURLProtocol.serve(handler)
        let tokens = SyncTokenStore(accessToken: "old", refreshToken: "refresh-1") { _ in }
        let client = try SyncAPIClient(
            address: SyncServerAddress(normalized: "https://\(host)/api"),
            session: session,
            clientVersion: "1.0 (7)",
            tokens: tokens,
        )
        return SyncEventStream(client: client, session: session)
    }

    @Test(arguments: [
        (["event: changes", "data: {}", ""], [.none, .changes, .none]),
        ([": ping", "", "data: {}"], [.none, .none, .none]),
        (["event: changes", ": ping", "data: {}"], [.none, .none, .none]),
        (["event: other", "data: {}", "event:changes", "data: {\"version\": 3}"], [.none, .none, .none, .changes]),
        (["event:expired"], [.expired]),
    ] as [([String], [SyncEventReader.Action])])
    func `each line becomes an action`(lines: [String], actions: [SyncEventReader.Action]) {
        var reader = SyncEventReader()
        #expect(lines.map { reader.read($0) } == actions)
    }

    @Test func `each cut waits longer, up to five minutes`() {
        var delays = SyncReconnectDelay()
        let waits = (0 ..< 11).map { _ in delays.afterCut() }
        #expect(waits.prefix(4) == [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])
        #expect(waits[8] == .seconds(256))
        #expect(waits.suffix(2) == [.seconds(300), .seconds(300)])
    }

    /// Review SY18: a server that says `expired` at each connection gets the growing wait.
    @Test func `a renewal reconnects right away, unless the previous one was recent`() {
        var delays = SyncReconnectDelay()
        let start = ContinuousClock.now
        #expect(delays.afterRenewal(at: start) == .zero)
        #expect(delays.afterRenewal(at: start + .seconds(10)) == .seconds(1))
        #expect(delays.afterRenewal(at: start + .seconds(20)) == .seconds(2))
        // Far from the previous one: right away, and the wait starts again from 1 second.
        #expect(delays.afterRenewal(at: start + .seconds(60)) == .zero)
        #expect(delays.afterCut() == .seconds(1))
    }

    @Test func `an event of another device reads the changes`() async throws {
        let requests = Requests()
        let stream = try stream { request, _ in
            guard requests.record(request) == 1 else {
                return MockURLProtocol.problem(401, "device_revoked")
            }
            return Self.events(": ping\n\nevent: changes\ndata: {\"version\": 3}\n\n")
        }
        defer { stream.stop() }
        var changes = 0
        var ended: SyncServerError?
        stream.onChanges = { changes += 1 }
        stream.onSessionEnded = { ended = $0 }
        stream.start()

        // The connection and its event; the end of the answer reconnects after 1 second, to a revoked device.
        try await waitUntil { ended != nil }
        #expect(changes == 2)
        #expect(ended?.code == "device_revoked")
        #expect(requests.all == ["/api/v1/sync/events old", "/api/v1/sync/events old"])
    }

    /// The token expires during the stream (`event: expired`) or before it (`401 token_expired`): it is renewed, and
    /// the stream reconnects with the new one.
    @Test(arguments: [true, false])
    func `an expired token is renewed and the stream reconnects`(expiresDuringStream: Bool) async throws {
        let requests = Requests()
        let stream = try stream { request, _ in
            _ = requests.record(request)
            if request.url?.path == "/api/v1/auth/refresh" {
                return try MockURLProtocol.json(200, ["accessToken": "new", "refreshToken": "refresh-2", "expiresIn": 900])
            }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer old" else {
                return MockURLProtocol.problem(401, "account_deleted")
            }
            return expiresDuringStream ? Self.events("event: expired\ndata: {}\n\n") : MockURLProtocol.problem(401, "token_expired")
        }
        defer { stream.stop() }
        var changes = 0
        var ended: SyncServerError?
        stream.onChanges = { changes += 1 }
        stream.onSessionEnded = { ended = $0 }
        stream.start()

        try await waitUntil { ended != nil }
        #expect(ended?.code == "account_deleted")
        #expect(changes == (expiresDuringStream ? 1 : 0))
        #expect(requests.all == ["/api/v1/sync/events old", "/api/v1/auth/refresh", "/api/v1/sync/events new"])
    }
}
