import Foundation

/// Message shown for a sync error: written by Matcha from the error's stable code (`SYNC.md` § 4.1), never the
/// server's text.
enum SyncErrorText {
    static func message(for error: any Error) -> String {
        if let problem = error as? SyncServerAddress.Problem {
            return problem == .insecure
                ? String(localized: "The address must start with https://. Only this Mac's own server can use http://.")
                : String(localized: "This address isn't valid.")
        }
        if let error = error as? SyncServerError {
            return message(forCode: error.code)
        }
        if let error = error as? SyncClientError {
            return message(for: error)
        }
        if let error = error as? SyncCryptoError {
            return error == .passwordTooShort
                ? String(localized: "The password must have at least 12 characters.")
                : String(localized: "The server's security settings are too weak.")
        }
        if let error = error as? URLError {
            return message(for: error)
        }
        return String(localized: "Sync failed.", comment: "Settings > Sync: unknown error")
    }

    static func message(forCode code: String) -> String {
        messages[code] ?? String(localized: "The server had a problem. Try again later.")
    }

    /// Messages of the server's codes (`SYNC.md` § 4.8).
    private static var messages: [String: String] {
        [
            SyncServerError.invalidCredentials: String(localized: "The email or the password is incorrect."),
            SyncServerError.registrationClosed: String(localized: "This server doesn't accept new accounts."),
            SyncServerError.invitationRequired: String(localized: "An invitation code is required, or the one entered isn't valid."),
            SyncServerError.emailTaken: String(localized: "An account already uses this email."),
            SyncServerError.weakKDF: String(localized: "The server's security settings are too weak."),
            SyncServerError.rateLimited: String(localized: "Too many attempts. Try again in a moment."),
            SyncServerError.unsupportedClient: String(localized: "This version of Matcha is too old for this server. Update Matcha."),
            SyncServerError.quotaExceeded: String(localized: "The account's space is full."),
            SyncServerError.unavailable: String(localized: "The server is under maintenance. Try again later."),
            SyncServerError.deviceRevoked: String(localized: "This Mac was disconnected from sync."),
            SyncServerError.accountDeleted: String(localized: "This sync account was deleted from another device."),
            SyncServerError.invalidToken: String(localized: "Sign in again to keep syncing."),
            SyncServerError.tokenExpired: String(localized: "Sign in again to keep syncing."),
        ]
    }

    private static func message(for error: SyncClientError) -> String {
        switch error {
        case .notASyncServer: String(localized: "No Matcha sync server answers at this address.")
        case .unreadableAnswer: String(localized: "The server's answer couldn't be read.")
        case .signedOut: String(localized: "Sign in again to keep syncing.")
        case .accountKeyUnreadable: String(localized: "The account's key couldn't be opened. Check the password or the recovery key.")
        case .keychain: String(localized: "The keychain refused access. Unlock it, then try again.")
        }
    }

    /// Certificates macOS doesn't trust: no exception, the message says why (`SYNC.md` § 4.1).
    private static let certificateErrors: Set<URLError.Code> = [
        .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
        .secureConnectionFailed,
    ]

    private static func message(for error: URLError) -> String {
        if certificateErrors.contains(error.code) {
            return String(localized: """
            The server's certificate isn't trusted by this Mac. Use a certificate macOS trusts: a public one (Let's \
            Encrypt), one from a private network (Tailscale), or your own authority installed in Keychain Access.
            """)
        }
        if error.code == .appTransportSecurityRequiresSecureConnection {
            return String(localized: "The address must start with https://. Only this Mac's own server can use http://.")
        }
        return String(localized: "The server can't be reached. Check the address and the connection.")
    }
}
