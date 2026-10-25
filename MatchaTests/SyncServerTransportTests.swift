import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// Transport to a sync server (task 7.7, `SYNC.md` § 4): address, errors, tokens, encryption, against a fake server.
@MainActor
struct SyncServerTransportTests {
    /// Counter shared with a fake server's handler.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func next() -> Int {
            lock.withLock {
                value += 1
                return value
            }
        }

        var count: Int {
            lock.withLock { value }
        }
    }

    private func client(_ host: String, _ session: URLSession, tokens: SyncTokenStore? = nil) throws -> SyncAPIClient {
        try SyncAPIClient(
            address: SyncServerAddress(normalized: "https://\(host)/api"),
            session: session,
            clientVersion: "1.0 (7)",
            tokens: tokens,
        )
    }

    @Test func `the typed address is normalized`() {
        let cases: [(String, String?)] = [
            ("sync.example.com", "https://sync.example.com"),
            ("HTTPS://Sync.Example.com:443/api/", "https://sync.example.com/api"),
            ("https://sync.example.com/api/v1?x=1#y", "https://sync.example.com/api"),
            ("http://127.0.0.1:8080", "http://127.0.0.1:8080"),
            ("http://localhost:8080/api", "http://localhost:8080/api"),
            ("ftp://sync.example.com", nil),
            ("", nil),
        ]
        for (typed, expected) in cases {
            #expect((try? SyncServerAddress.parse(typed).get())?.normalized == expected, "\(typed)")
        }
        #expect(SyncServerAddress.parse("http://sync.example.com") == .failure(.insecure))
        #expect(SyncServerAddress(normalized: "https://sync.example.com/api").apiBase?.absoluteString == "https://sync.example.com/api/v1")
    }

    @Test func `an error answer gives its code and its wait`() async throws {
        let (host, session) = MockURLProtocol.serve { request, _ in
            #expect(request.value(forHTTPHeaderField: "Matcha-Client") == "1.0 (7)")
            return MockURLProtocol.problem(429, "rate_limited", headers: ["Retry-After": "30"])
        }
        let api = try client(host, session)
        await #expect(throws: SyncServerError(status: 429, code: "rate_limited", retryAfter: 30)) { try await api.server() }
    }

    @Test func `an expired token is renewed once for all the requests waiting`() async throws {
        let renewals = Counter()
        let (host, session) = MockURLProtocol.serve { request, _ in
            switch request.url?.path {
            case "/api/v1/auth/refresh":
                _ = renewals.next()
                Thread.sleep(forTimeInterval: 0.1)
                return try MockURLProtocol.json(200, ["accessToken": "new", "refreshToken": "refresh-2", "expiresIn": 900])
            default:
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer new" else {
                    return MockURLProtocol.problem(401, "token_expired")
                }
                return try MockURLProtocol.json(200, ["devices": [] as [Any]])
            }
        }
        let saved = Counter()
        let tokens = SyncTokenStore(accessToken: "old", refreshToken: "refresh-1") { renewed in
            #expect(renewed.refreshToken == "refresh-2")
            _ = saved.next()
        }
        let api = try client(host, session, tokens: tokens)
        async let first = api.devices()
        async let second = api.devices()
        async let third = api.devices()
        _ = try await (first, second, third)
        #expect(renewals.count == 1)
        #expect(saved.count == 1)
        #expect(await tokens.accessToken == "new")
    }

    @Test func `contents leave encrypted and come back decrypted`() async throws {
        let accountKey = SymmetricKey(size: .bits256)
        let stored = NSLock()
        nonisolated(unsafe) var pushed: [[String: Any]] = []
        let (host, session) = MockURLProtocol.serve { request, body in
            switch request.url?.path {
            case "/api/v1/sync/push":
                #expect(request.value(forHTTPHeaderField: "Idempotency-Key") != nil)
                let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let changes = object?["changes"] as? [[String: Any]] ?? []
                stored.withLock { pushed = changes }
                // `baseVersion` written as null for a creation.
                #expect(changes.first?.keys.contains("baseVersion") == true)
                #expect(changes.first?["baseVersion"] is NSNull)
                let results: [[String: Any]] = [
                    ["id": changes[0]["id"] ?? "", "status": "applied", "version": 12],
                    ["id": changes[1]["id"] ?? "", "status": "rejected", "code": "payload_too_large"],
                ]
                return try MockURLProtocol.json(200, ["results": results])
            case "/api/v1/sync/changes":
                let records = stored.withLock { pushed }.enumerated().map { index, change -> [String: Any] in
                    ["id": change["id"] ?? "", "version": index + 1, "deleted": false, "keyVersion": 1, "payload": change["payload"] ?? ""]
                }
                let tampered: [String: Any] = ["id": UUID().uuidString, "version": 9, "keyVersion": 1, "payload": "AQID"]
                return try MockURLProtocol.json(200, ["changes": records + [tampered], "cursor": "c_9", "hasMore": false])
            default:
                return MockURLProtocol.problem(404, "not_found")
            }
        }
        let tokens = SyncTokenStore(accessToken: "token", refreshToken: "refresh") { _ in }
        let api = try client(host, session, tokens: tokens)
        let transport = SyncServerTransport(
            client: api,
            accountKey: accountKey,
            server: SyncServerInfo(api: 1, features: ["events", "blobs"]),
        )
        let content = SyncContent(
            fields: .profile(SyncProfileFields(name: "Personnel", order: 0)),
            modifiedAt: .now,
            modifiedBy: UUID(),
        )
        let changes = [
            SyncOutgoingChange(id: UUID(), baseVersion: nil, content: content),
            SyncOutgoingChange(id: UUID(), baseVersion: 3, content: content),
        ]
        let batch = try transport.prepare(changes)
        // The body never carries the name in clear text.
        #expect(String(bytes: batch.body, encoding: .utf8)?.range(of: "Personnel") == nil)
        #expect(try await transport.push(batch) == [.applied(version: 12), .rejected(code: "payload_too_large")])

        let page = try await transport.changes(since: nil)
        #expect(page.records.prefix(2).map(\.content) == [content, content])
        // A content that can't be decrypted is kept unreadable, never applied.
        #expect(page.records.last?.content == nil)
        #expect(page.cursor == "c_9")
    }

    @Test func `a batch too big for the server is split by the engine`() async throws {
        let (host, session) = MockURLProtocol.serve { _, _ in MockURLProtocol.problem(413, "request_too_large") }
        let tokens = SyncTokenStore(accessToken: "token", refreshToken: "refresh") { _ in }
        let transport = try SyncServerTransport(
            client: client(host, session, tokens: tokens),
            accountKey: SymmetricKey(size: .bits256),
            server: SyncServerInfo(api: 1),
        )
        let content = SyncContent(fields: .profile(SyncProfileFields(name: "P", order: 0)), modifiedAt: .now, modifiedBy: UUID())
        let batch = try transport.prepare([SyncOutgoingChange(id: UUID(), baseVersion: nil, content: content)])
        await #expect(throws: SyncTransportError.batchTooLarge) { try await transport.push(batch) }
    }

    /// Review SY2: the results are matched by identifier; another record's result, or a current record of another
    /// identifier, makes the answer unreadable.
    @Test func `push results are matched by identifier, never by position`() throws {
        let content = SyncContent(fields: .profile(SyncProfileFields(name: "P", order: 0)), modifiedAt: .now, modifiedBy: UUID())
        let first = SyncOutgoingChange(id: UUID(), baseVersion: nil, content: content)
        let second = SyncOutgoingChange(id: UUID(), baseVersion: 3, content: content)
        func result(_ id: UUID?, current: UUID? = nil) -> SyncServerPushResult {
            SyncServerPushResult(
                id: id,
                status: current == nil ? "applied" : "conflict",
                version: 4,
                current: current.map { SyncServerRecord(id: $0, version: 4, payload: "") },
            )
        }
        let reversed = try SyncServerTransport.results([result(second.id), result(first.id)], for: [first, second])
        #expect(reversed.map(\.id) == [first.id, second.id])
        #expect(try SyncServerTransport.results([result(first.id), result(second.id, current: second.id)], for: [first, second]).count == 2)

        let wrong: [[SyncServerPushResult]] = [
            [result(first.id)],
            [result(first.id), result(UUID())],
            [result(first.id), result(first.id)],
            [result(first.id), result(nil)],
            [result(first.id), result(second.id, current: first.id)],
        ]
        for results in wrong {
            #expect(throws: SyncClientError.unreadableAnswer) { try SyncServerTransport.results(results, for: [first, second]) }
        }
    }

    /// Review SY21: a redirection is never followed; its answer says the address isn't the API's.
    @Test func `a redirection is refused`() async throws {
        let (host, session) = MockURLProtocol.serve { _, _ in
            MockResponse(status: 307, headers: ["Location": "https://elsewhere.example/api/v1/server"])
        }
        let api = try client(host, session)
        await #expect(throws: SyncClientError.notASyncServer) { try await api.server() }
    }
}
