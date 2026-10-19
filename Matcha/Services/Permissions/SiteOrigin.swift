import Foundation

/// Origin of a page: scheme, host and port, key of the permission decisions (task 5.2). Scheme and host are lowercase;
/// the port is kept only if it differs from the scheme's (WebKit gives 0 for the default port). No origin without a
/// host (local file, `about:`, `data:`): nothing is remembered there.
nonisolated struct SiteOrigin: Hashable, Sendable {
    let scheme: String
    let host: String
    /// Explicit port; nil for the scheme's default port.
    let port: Int?

    init?(scheme: String, host: String, port: Int?) {
        var host = host.lowercased()
        // IPv6: kept without brackets, put back in the key.
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        let scheme = scheme.lowercased()
        guard !scheme.isEmpty, !host.isEmpty else {
            return nil
        }
        self.scheme = scheme
        self.host = host
        self.port = port.flatMap { $0 > 0 && $0 != Self.defaultPort(of: scheme) ? $0 : nil }
    }

    init?(url: URL) {
        guard let scheme = url.scheme, let host = url.host(percentEncoded: false) else {
            return nil
        }
        self.init(scheme: scheme, host: host, port: url.port)
    }

    /// Reads a saved key (`key`) back.
    init?(key: String) {
        guard let url = URL(string: key) else {
            return nil
        }
        self.init(url: url)
    }

    /// Origin of a website (http or https); nil for any other page.
    static func web(of url: URL?) -> SiteOrigin? {
        guard let origin = url.flatMap(SiteOrigin.init(url:)), origin.isWeb else {
            return nil
        }
        return origin
    }

    static func defaultPort(of scheme: String) -> Int? {
        ["http": 80, "https": 443][scheme]
    }

    /// Saved key: “https://example.com”, “http://localhost:8080”, “http://[::1]:3000”.
    var key: String {
        "\(scheme)://\(hostForAddress)\(port.map { ":\($0)" } ?? "")"
    }

    var isWeb: Bool {
        scheme == "http" || scheme == "https"
    }

    /// Displayed host: without “www.”, with the port if it is not the default one.
    var displayHost: String {
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let shown = domain.contains(":") ? "[\(domain)]" : domain
        return port.map { "\(shown):\($0)" } ?? shown
    }

    /// Name shown in the banner, the panel and the settings: the host, preceded by the scheme if it is not https
    /// (“http://localhost:8080”) to tell apart two origins of the same host.
    var displayName: String {
        scheme == "https" ? displayHost : "\(scheme)://\(displayHost)"
    }

    private var hostForAddress: String {
        host.contains(":") ? "[\(host)]" : host
    }
}
