import Foundation

/// Turns the text typed in the address field into a URL:
/// a full address as is, a host to which a scheme is added, or a search.
nonisolated struct AddressResolver: Sendable {
    var searchEngine = SearchEngine.defaultEngine

    /// Schemes accepted as is.
    static let directSchemes: Set<String> = ["http", "https", "file", "about"]

    /// URL to open for `input`, or nil if the text is empty.
    func resolve(_ input: String) -> URL? {
        interpret(input)?.url
    }

    /// Reading of `input`: an address (accepted scheme as is, or a host to which a scheme is added)
    /// or a search; nil if the text is empty.
    func interpret(_ input: String) -> AddressInterpretation? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), Self.directSchemes.contains(scheme) {
            return .address(url)
        }
        if let url = hostURL(for: text) {
            return .address(url)
        }
        return searchEngine.searchURL(for: text).map(AddressInterpretation.search)
    }

    /// Full URL if `text` looks like “host[:port][/path]”, with no space.
    /// Local hosts (localhost, IP addresses, `.local`) get `http://`, the others `https://`.
    private func hostURL(for text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else {
            return nil
        }
        let authorityEnd = text.firstIndex { "/?#".contains($0) } ?? text.endIndex
        guard let kind = HostKind(authority: text[..<authorityEnd]) else {
            return nil
        }
        let scheme = kind == .local ? "http" : "https"
        return URL(string: "\(scheme)://\(text)")
    }
}

/// What a typed text designates: an address to open or a search to run.
nonisolated enum AddressInterpretation: Equatable, Sendable {
    case address(URL)
    /// Search for the text on the chosen engine; the URL is that of the results page.
    case search(URL)

    var url: URL {
        switch self {
        case let .address(url), let .search(url): url
        }
    }
}

/// Nature of the “host[:port]” part of an address typed without a scheme.
private nonisolated enum HostKind {
    /// Public domain name, served over HTTPS.
    case domain
    /// localhost, IP address or `.local` name: development servers, routers, printers.
    case local

    /// Nil if `authority` does not look like a host.
    init?(authority: Substring) {
        // An “@” rather signals an e-mail address, which we search for.
        guard !authority.isEmpty, !authority.contains("@") else {
            return nil
        }
        if authority.hasPrefix("[") {
            guard Self.isBracketedIPv6(authority) else {
                return nil
            }
            self = .local
            return
        }
        var host = authority
        if let colon = authority.lastIndex(of: ":") {
            guard Self.isPort(authority[authority.index(after: colon)...]) else {
                return nil
            }
            host = authority[..<colon]
        }
        let name = host.lowercased()
        if name == "localhost" || Self.isIPv4(name) {
            self = .local
        } else if Self.isDomainName(name) {
            self = name.hasSuffix(".local") || name.hasSuffix(".localhost") ? .local : .domain
        } else {
            return nil
        }
    }

    /// “[::1]” or “[::1]:8080”.
    private static func isBracketedIPv6(_ authority: Substring) -> Bool {
        guard let close = authority.firstIndex(of: "]") else {
            return false
        }
        let address = authority[authority.index(after: authority.startIndex) ..< close]
        let rest = authority[authority.index(after: close)...]
        let validRest = rest.isEmpty || (rest.first == ":" && isPort(rest.dropFirst()))
        let validAddress = address.contains(":") && address.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        return validRest && validAddress
    }

    private static func isPort(_ text: Substring) -> Bool {
        guard (1 ... 5).contains(text.count), text.allSatisfy(isASCIIDigit), let port = Int(text) else {
            return false
        }
        return (1 ... 65535).contains(port)
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            (1 ... 3).contains(part.count) && part.allSatisfy(isASCIIDigit) && (Int(part) ?? 256) <= 255
        }
    }

    /// At least two labels separated by dots, the last one containing a letter:
    /// “apple.com” yes, “6.4” no. A trailing dot is tolerated.
    private static func isDomainName(_ text: String) -> Bool {
        var labels = text.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count > 2, labels.last?.isEmpty == true {
            labels.removeLast()
        }
        guard labels.count >= 2, labels.allSatisfy(isLabel), let topLevel = labels.last else {
            return false
        }
        return topLevel.contains(where: \.isLetter)
    }

    private static func isLabel(_ label: Substring) -> Bool {
        guard let first = label.first, let last = label.last, first != "-", last != "-" else {
            return false
        }
        return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}
