import Foundation

/// Text forms compared by the command bar: folded text (without case, accents or width), words, and readable
/// addresses.
nonisolated enum CommandText {
    /// Text without case, accents or full width, spaces collapsed and trimmed at the edges:
    /// “CAFÉ  Crème” → “cafe creme”.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Words of a folded text: anything that is neither a letter nor a digit separates them.
    static func words(_ folded: String) -> [Substring] {
        folded.split { !$0.isLetter && !$0.isNumber }
    }

    /// Readable address: for a web page, the host without “www.”, the port if it is not the scheme's, the path
    /// without trailing “/” and the query, without fragment; the path of a file; otherwise the whole address without
    /// fragment (`about:blank?one`).
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

    /// Key of an address for spotting duplicates: `http` and `https`, “www.” and the host's case do not count; other
    /// schemes keep their name (`about:blank?one`).
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

    /// Folded text without a leading “https://” or “http://”, then without “www.”:
    /// “https://www.git” → “git”.
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

    /// “host[:port]/path?query” of a web address, nil if it has no host.
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
