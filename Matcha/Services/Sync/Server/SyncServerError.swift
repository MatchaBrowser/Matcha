import Foundation

/// Error answered by a sync server (`application/problem+json`, `SYNC.md` § 4.8): its stable `code`, from which the
/// interface writes its own translated message, and the wait asked by `Retry-After`.
nonisolated struct SyncServerError: Error, Equatable, Sendable {
    let status: Int
    let code: String
    /// Seconds to wait before trying again (`429`, `503`).
    let retryAfter: TimeInterval?

    init(status: Int, code: String, retryAfter: TimeInterval? = nil) {
        self.status = status
        self.code = code
        self.retryAfter = retryAfter
    }

    static let invalidRequest = "invalid_request"
    static let weakKDF = "weak_kdf"
    static let invalidCredentials = "invalid_credentials"
    static let tokenExpired = "token_expired"
    static let invalidToken = "invalid_token"
    static let deviceRevoked = "device_revoked"
    static let accountDeleted = "account_deleted"
    static let registrationClosed = "registration_closed"
    static let invitationRequired = "invitation_required"
    static let notFound = "not_found"
    static let emailTaken = "email_taken"
    static let blobExists = "blob_exists"
    static let cursorExpired = "cursor_expired"
    static let requestTooLarge = "request_too_large"
    static let blobTooLarge = "blob_too_large"
    static let unsupportedClient = "unsupported_client"
    static let rateLimited = "rate_limited"
    static let serverError = "server_error"
    static let quotaExceeded = "quota_exceeded"
    static let unavailable = "unavailable"

    /// This Mac is no longer signed in: revoked, account deleted, or tokens unknown.
    var endsSession: Bool {
        [Self.deviceRevoked, Self.accountDeleted, Self.invalidToken].contains(code)
    }
}

/// Problems on this Mac's side, before or after the server.
nonisolated enum SyncClientError: Error, Equatable, Sendable {
    /// Not a sync server, or another version of the API.
    case notASyncServer
    /// The answer couldn't be read.
    case unreadableAnswer
    /// Not signed in to a sync account.
    case signedOut
    /// The account key couldn't be opened: envelope tampered with, or another password.
    case accountKeyUnreadable
    /// The keychain refused (locked, access denied): an error, not an absence.
    case keychain(OSStatus)
}

/// Problem object of an error answer.
nonisolated struct SyncProblem: Decodable, Sendable {
    var status: Int?
    var code: String?
    var title: String?
}
