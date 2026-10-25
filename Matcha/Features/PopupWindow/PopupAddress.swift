import Foundation

/// Address shown by the bar of a sign-in window (task 5.8): you must see which site asks for the password,
/// whatever title the page gives itself. The window title comes from the page, this bar never does.
nonisolated struct PopupAddress: Equatable, Sendable {
    /// From the address alone: https, http, or not a site (local file, `about:`, `data:`). The bar shows the page's
    /// (`BrowserTab.security`), which also knows about unencrypted parts.
    typealias Security = PageSecurity

    /// The host (without “www.”, with the port if it is not the default one) for a site; the file name for a local
    /// file; `about:blank`; the website that made a `blob:` page (`blob:example.com`, review WB15), never its path;
    /// otherwise only the scheme (`data:`), never the content of a `data:` address.
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
        security = PageSecurity.of(url, hasOnlySecureContent: true)
        if let origin = SiteOrigin.web(of: url) {
            text = origin.displayHost
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if url.isFileURL {
            text = url.lastPathComponent
        } else if let origin = SiteOrigin(url: url) {
            text = "\(origin.scheme)://\(origin.displayHost)"
        } else if scheme == "about" {
            text = url.absoluteString
        } else if scheme == "blob", let inner = URL(string: String(url.absoluteString.dropFirst(5))), let origin = SiteOrigin(url: inner) {
            text = "blob:\(origin.displayName)"
        } else {
            text = scheme.isEmpty ? "" : "\(scheme):"
        }
    }
}
