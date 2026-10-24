import Foundation

/// Tokens of this Mac's session (`SYNC.md` § 4.1). The refresh token serves only once, and the server revokes the
/// device if one is reused: only one renewal at a time, which the sync cycle, the event stream and a package download
/// all wait for, and the new tokens are written to the keychain (`save`) before being used.
actor SyncTokenStore {
    private(set) var accessToken: String
    private var refreshToken: String
    private var renewal: Task<SyncRefreshResponse, any Error>?
    private let save: @Sendable (_ tokens: SyncRefreshResponse) throws -> Void

    init(accessToken: String, refreshToken: String, save: @escaping @Sendable (_ tokens: SyncRefreshResponse) throws -> Void) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.save = save
    }

    /// A valid access token after `failed` was refused as expired: the one of a renewal already done or in progress,
    /// otherwise a new one.
    func renewed(
        after failed: String,
        using renew: @escaping @Sendable (_ refreshToken: String) async throws -> SyncRefreshResponse,
    ) async throws -> String {
        if accessToken != failed {
            return accessToken
        }
        if let renewal {
            return try await renewal.value.accessToken
        }
        let refreshToken = refreshToken
        let save = save
        let task = Task {
            let tokens = try await renew(refreshToken)
            try save(tokens)
            return tokens
        }
        renewal = task
        defer { renewal = nil }
        let tokens = try await task.value
        accessToken = tokens.accessToken
        self.refreshToken = tokens.refreshToken
        return tokens.accessToken
    }
}

/// Gap between this Mac's clock and the server's, read from the `Date` header of each answer (`SYNC.md` § 2.8): it
/// only warns, it never dates anything (the header isn't authenticated).
actor SyncServerClock {
    /// This Mac's time minus the server's, in seconds; nil before a first answer.
    private(set) var offset: TimeInterval?

    func record(_ header: String?, receivedAt now: Date = .now) {
        guard let header, let date = Self.formatter.date(from: header) else {
            return
        }
        offset = now.timeIntervalSince(date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}
