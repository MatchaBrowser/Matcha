import Foundation
import OSLog

/// Event stream of the server (`GET /v1/sync/events`, `SYNC.md` § 4.6): each time another device of the account had
/// changes applied, the changes are read again, and also on each connection (what happened in between). The server
/// closes the stream when the access token expires, after `event: expired`: the token is renewed (one renewal at a
/// time) and the stream reconnects right away, unless the previous renewal was less than 30 seconds ago: a server that
/// says `expired` at each connection gets the growing delay (review SY18). Any other cut (network, answer other than
/// `200`, no `ping` for 90 seconds) reconnects after a growing delay, from 1 second to 5 minutes
/// (`SyncReconnectDelay`). The lines are read by `SyncEventReader`.
@MainActor
final class SyncEventStream {
    private let client: SyncAPIClient
    /// Requests without data for 90 seconds end (the server sends a `ping` every 30 seconds).
    private let session: URLSession
    private var task: Task<Void, Never>?
    /// Something changed on the server, or the stream (re)connected: read the changes.
    var onChanges: (() -> Void)?
    /// The session ended (revoked device, deleted account, unknown tokens): the stream stops.
    var onSessionEnded: ((SyncServerError) -> Void)?

    init(client: SyncAPIClient, session: URLSession = SyncAPIClient.makeSession(timeout: 90)) {
        self.client = client
        self.session = session
    }

    func start() {
        guard task == nil else {
            return
        }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    /// Ends the stream and its session (review SY18): a stream is never started again.
    func stop() {
        task?.cancel()
        task = nil
        session.invalidateAndCancel()
    }

    private func run() async {
        var delays = SyncReconnectDelay()
        while !Task.isCancelled {
            do {
                try await listen()
                let wait = delays.afterRenewal(at: .now)
                if wait > .zero {
                    try? await Task.sleep(for: wait)
                }
            } catch let error as SyncServerError where error.endsSession {
                onSessionEnded?(error)
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                Logger.sync.notice("Event stream cut: \(error.logSummary, privacy: .public)")
                try? await Task.sleep(for: delays.afterCut())
            }
        }
    }

    /// One connection; returns to reconnect right away (expired token), throws to reconnect after a delay.
    private func listen() async throws {
        guard let tokens = client.tokens else {
            throw SyncClientError.signedOut
        }
        let token = await tokens.accessToken
        var request = client.eventsRequest()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(for: request, delegate: client.redirects)
        guard let http = response as? HTTPURLResponse else {
            throw SyncClientError.unreadableAnswer
        }
        guard http.statusCode == 200 else {
            let error = try await Self.error(in: bytes, response: http)
            guard error.code == SyncServerError.tokenExpired else {
                throw error
            }
            _ = try await renew(after: token)
            return
        }
        onChanges?()
        var reader = SyncEventReader()
        // Lines of a reasonable length: a server that never ends one can't make the memory grow (review TR2).
        for try await line in BoundedLines(base: bytes, limit: Self.maximumLineLength) {
            switch reader.read(line) {
            case .expired:
                _ = try await renew(after: token)
                return
            case .changes:
                onChanges?()
            case .none:
                break
            }
        }
        throw URLError(.networkConnectionLost)
    }

    /// Longest line of the stream, and of the error answer read.
    static let maximumLineLength = 65536

    /// Error answer of the stream, read from its first bytes only.
    private static func error(in bytes: URLSession.AsyncBytes, response: HTTPURLResponse) async throws -> SyncServerError {
        let data = try await BoundedRead.prefix(of: bytes, limit: maximumLineLength)
        return SyncAPIClient.error(from: data, response: response)
    }

    private func renew(after token: String) async throws -> String {
        guard let tokens = client.tokens else {
            throw SyncClientError.signedOut
        }
        let client = client
        return try await tokens.renewed(after: token) { refreshToken in
            try await client.renew(refreshToken)
        }
    }
}
