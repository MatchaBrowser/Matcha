import WebKit

extension WKSecurityOrigin {
    /// The origin as a permissions key; nil without a host (local file, opaque origin of a `data:` or sandboxed frame).
    var siteOrigin: SiteOrigin? {
        SiteOrigin(scheme: `protocol`, host: host, port: port)
    }
}
