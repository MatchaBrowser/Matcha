import Foundation

/// Address shown by the bar of a sign-in window (task 5.8): you must see which site asks for the password,
/// whatever title the page gives itself. The window title comes from the page, this bar never does.
nonisolated struct PopupAddress: Equatable, Sendable {
    enum Security: Equatable, Sendable {
        /// https: encrypted connection (padlock).
        case secure
        /// http: “Not Secure”.
        case notSecure
        /// Not a site (local file, `about:`, `data:`): nothing.
        case none
    }

    /// The host (without “www.”, with the port if it is not the default one) for a site; the file name for a local
    /// file; `about:blank`; otherwise only the scheme (`data:`), never the content of a `data:` address.
    let text: String
    let security: Security
}

nonisolated extension PopupAddress {
    init(url: URL?) {
        guard let url else {
            text = ""
            security = .none
            return
        }
        if let origin = SiteOrigin.web(of: url) {
            text = origin.displayHost
            security = origin.scheme == "https" ? .secure : .notSecure
            return
        }
        security = .none
        let scheme = url.scheme?.lowercased() ?? ""
        if url.isFileURL {
            text = url.lastPathComponent
        } else if let origin = SiteOrigin(url: url) {
            text = "\(origin.scheme)://\(origin.displayHost)"
        } else if scheme == "about" {
            text = url.absoluteString
        } else {
            text = scheme.isEmpty ? "" : "\(scheme):"
        }
    }
}
