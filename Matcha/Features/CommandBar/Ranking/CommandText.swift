import Foundation

/// Formes de texte comparées par la barre de commande : texte replié (sans casse, accents ni
/// largeur), mots, et adresses lisibles.
nonisolated enum CommandText {
    /// Texte sans casse, accents ni pleine largeur, espaces regroupés et retirés aux bords :
    /// « CAFÉ  Crème » → « cafe creme ».
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Mots d'un texte replié : tout ce qui n'est ni une lettre ni un chiffre les sépare.
    static func words(_ folded: String) -> [Substring] {
        folded.split { !$0.isLetter && !$0.isNumber }
    }

    /// Adresse lisible : pour une page web, l'hôte sans « www. », le port s'il n'est pas celui du
    /// schéma, le chemin sans « / » final et la requête, sans fragment ; le chemin d'un fichier ;
    /// sinon l'adresse entière sans fragment (`about:blank?one`).
    static func displayURL(_ url: URL) -> String {
        switch url.scheme?.lowercased() {
        case "http", "https":
            webDisplay(url, lowercasingHost: false) ?? withoutFragment(url.absoluteString)
        case "file":
            url.path(percentEncoded: false)
        default:
            withoutFragment(url.absoluteString)
        }
    }

    /// Clé d'une adresse pour repérer les doublons : `http` et `https`, « www. » et la casse de
    /// l'hôte n'y comptent pas ; les autres schémas gardent leur nom (`about:blank?one`).
    static func urlKey(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https", let display = webDisplay(url, lowercasingHost: true) {
            return display
        }
        let display = displayURL(url)
        guard let scheme else {
            return display
        }
        let prefix = scheme + ":"
        let rest = display.lowercased().hasPrefix(prefix) ? String(display.dropFirst(prefix.count)) : display
        return prefix + rest
    }

    /// Texte replié sans « https:// » ou « http:// » initial, puis sans « www. » :
    /// « https://www.git » → « git ».
    static func stripURLPrefixes(_ folded: String) -> String {
        var text = Substring(folded)
        if let scheme = ["https://", "http://"].first(where: { text.hasPrefix($0) }) {
            text = text.dropFirst(scheme.count)
        }
        if text.hasPrefix("www.") {
            text = text.dropFirst(4)
        }
        return String(text)
    }

    /// « hôte[:port]/chemin?requête » d'une adresse web, nil si elle n'a pas d'hôte.
    private static func webDisplay(_ url: URL, lowercasingHost: Bool) -> String? {
        guard var host = url.host(), !host.isEmpty else {
            return nil
        }
        if lowercasingHost {
            host = host.lowercased()
        }
        if host.lowercased().hasPrefix("www.") {
            host.removeFirst(4)
        }
        if host.contains(":") {
            host = "[\(host)]"
        }
        let defaultPort = url.scheme?.lowercased() == "http" ? 80 : 443
        if let port = url.port, port != defaultPort {
            host += ":\(port)"
        }
        var path = url.path(percentEncoded: false)
        if path.hasSuffix("/") {
            path.removeLast()
        }
        let query = url.query(percentEncoded: false).map { $0.isEmpty ? "" : "?\($0)" } ?? ""
        return host + path + query
    }

    private static func withoutFragment(_ address: String) -> String {
        address.firstIndex(of: "#").map { String(address[..<$0]) } ?? address
    }
}
