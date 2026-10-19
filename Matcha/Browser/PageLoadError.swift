import Foundation

/// A page that couldn't load (audit K5): shown in place of the page with what to do about it (“Try Again”, the
/// certificate). WebKit itself shows nothing: the tab stayed blank or on the previous page. Pure type.
nonisolated struct PageLoadError: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The Mac isn't connected.
        case offline
        /// The website's name leads nowhere.
        case serverNotFound
        case timedOut
        /// The server refused or didn't answer the connection.
        case cannotConnect
        /// The website's certificate isn't valid: maybe someone impersonating it.
        case certificate
        /// The website wants a user name and password that weren't given.
        case loginRequired
        case other
    }

    let kind: Kind
    /// The address that failed.
    let url: URL
    let domain: String
    let code: Int
    /// The system's description, for an error without a message of its own.
    let detail: String

    var host: String {
        url.host(percentEncoded: false) ?? url.absoluteString
    }

    /// nil for a failure that isn't one for the user: a load cancelled (Stop, another load started), a link that became
    /// a download, a navigation the app turned elsewhere (other app, new tab).
    init?(_ error: NSError, url: URL?) {
        guard let url, !Self.isSilent(error) else {
            return nil
        }
        self.url = url
        domain = error.domain
        code = error.code
        detail = error.localizedDescription
        kind = error.domain == NSURLErrorDomain ? Self.kind(ofURLError: error.code) : .other
    }

    private static func isSilent(_ error: NSError) -> Bool {
        switch error.domain {
        case NSURLErrorDomain:
            error.code == NSURLErrorCancelled
        // 102: load interrupted by a policy change (download, navigation cancelled by the app); 204: handled by a
        // plug-in.
        case "WebKitErrorDomain":
            [102, 204].contains(error.code)
        default:
            false
        }
    }

    private static let offlineCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
    ]
    private static let certificateCodes: Set<Int> = [
        NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
    ]

    private static func kind(ofURLError code: Int) -> Kind {
        if offlineCodes.contains(code) {
            return .offline
        }
        if certificateCodes.contains(code) {
            return .certificate
        }
        return switch code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: .serverNotFound
        case NSURLErrorTimedOut: .timedOut
        case NSURLErrorCannotConnectToHost: .cannotConnect
        case NSURLErrorUserCancelledAuthentication, NSURLErrorUserAuthenticationRequired: .loginRequired
        default: .other
        }
    }
}
