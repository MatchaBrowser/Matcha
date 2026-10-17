import Foundation

/// Origine d'une page : schéma, hôte et port, clé des décisions de permission (tâche 5.2). Schéma et hôte sont en
/// minuscules ; le port n'est gardé que s'il diffère de celui du schéma (WebKit donne 0 pour le port par défaut).
/// Pas d'origine sans hôte (fichier local, `about:`, `data:`) : rien n'y est retenu.
nonisolated struct SiteOrigin: Hashable, Sendable {
    let scheme: String
    let host: String
    /// Port explicite ; nil pour le port par défaut du schéma.
    let port: Int?

    init?(scheme: String, host: String, port: Int?) {
        var host = host.lowercased()
        // IPv6 : gardé sans crochets, remis dans la clé.
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

    /// Relit une clé enregistrée (`key`).
    init?(key: String) {
        guard let url = URL(string: key) else {
            return nil
        }
        self.init(url: url)
    }

    /// Origine d'un site web (http ou https) ; nil pour toute autre page.
    static func web(of url: URL?) -> SiteOrigin? {
        guard let origin = url.flatMap(SiteOrigin.init(url:)), origin.isWeb else {
            return nil
        }
        return origin
    }

    static func defaultPort(of scheme: String) -> Int? {
        ["http": 80, "https": 443][scheme]
    }

    /// Clé enregistrée : « https://example.com », « http://localhost:8080 », « http://[::1]:3000 ».
    var key: String {
        "\(scheme)://\(hostForAddress)\(port.map { ":\($0)" } ?? "")"
    }

    var isWeb: Bool {
        scheme == "http" || scheme == "https"
    }

    /// Hôte affiché : sans « www. », avec le port s'il n'est pas celui par défaut.
    var displayHost: String {
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let shown = domain.contains(":") ? "[\(domain)]" : domain
        return port.map { "\(shown):\($0)" } ?? shown
    }

    /// Nom montré dans le bandeau, le panneau et les réglages : l'hôte, précédé du schéma s'il n'est pas https
    /// (« http://localhost:8080 ») pour distinguer deux origines du même hôte.
    var displayName: String {
        scheme == "https" ? displayHost : "\(scheme)://\(displayHost)"
    }

    private var hostForAddress: String {
        host.contains(":") ? "[\(host)]" : host
    }
}
