import Foundation

/// Security of a displayed page, shown next to its address (audit W5): padlock for an encrypted website, whose
/// certificate is one click away; “Not Secure” for an unencrypted one. Pure type.
nonisolated enum PageSecurity: Equatable, Sendable {
    /// https, and everything on the page came encrypted.
    case secure
    /// https, but parts of the page (images, media) came without encryption.
    case partlySecure
    /// http.
    case notSecure
    /// https with a certificate that isn't valid, which the user chose to accept (`CertificateExceptions`).
    case invalidCertificate
    /// Not a website (local file, `about:`, `data:`, extension page…): nothing to show.
    case none

    /// Security of the page at `url`; `hasOnlySecureContent`: WebKit's verdict on everything it loaded.
    static func of(_ url: URL?, hasOnlySecureContent: Bool) -> PageSecurity {
        guard let origin = SiteOrigin.web(of: url) else {
            return .none
        }
        guard origin.scheme == "https" else {
            return .notSecure
        }
        return hasOnlySecureContent ? .secure : .partlySecure
    }

    /// True if the connection is encrypted: its certificate can be shown.
    var hasCertificate: Bool {
        [.secure, .partlySecure, .invalidCertificate].contains(self)
    }
}
