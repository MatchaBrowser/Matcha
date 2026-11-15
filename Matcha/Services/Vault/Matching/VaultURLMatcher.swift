import Foundation

/// Which logins a page, or a frame, may receive (`VAULT.md` § 8.2): a login's addresses compared with the page's
/// address under the login's rule (`VaultURLMatch`). Only `http` and `https` count; a login saved in `https` never
/// matches an `http` page, and one saved in `http` matches the `https` page too, its `http` page with a warning.
/// Addresses are compared each time, never rewritten: a new version of the public suffix list applies to every login
/// at once. Pure type.
nonisolated struct VaultURLMatcher: Sendable {
    let publicSuffixList: PublicSuffixList

    /// Address of a login, as typed or as kept in `urls`, ready to compare: “https://” is added when it has no scheme
    /// (“example.com/login”, “localhost:3000”). Nil unless it is an `http` or `https` address with a host.
    static func normalizedItemURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: hasScheme(trimmed) ? trimmed : "https://" + trimmed),
              VaultURLAddress(url) != nil
        else {
            return nil
        }
        return url
    }

    /// True if `text` starts with a scheme and “://” (“ftp://”, “https://”); “localhost:3000” or
    /// “example.com/?next=https://…” have none.
    private static func hasScheme(_ text: String) -> Bool {
        guard let separator = text.range(of: "://"), let first = text.first, first.isASCII, first.isLetter else {
            return false
        }
        return text[..<separator.lowerBound].allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || "+-.".contains(character))
        }
    }

    /// How `page` matches a login saved on `itemURL` under `rule`. `site`: the same registrable domain, an IP
    /// address, `localhost`, a single label or a host that is itself a public suffix being taken whole, the port
    /// left out. `host`: the same host and the same port. `page`: the same host, port and path (query and fragment
    /// left out, a final slash ignored). A port is compared after the default of its own scheme is dropped, and the
    /// scheme as § 8.2 says: so a login saved on “http://example.com/login” matches “https://example.com/login/”.
    ///
    /// For a frame, `page` is the frame's own address (the URL of its document), never the tab's: a frame is filled
    /// only if its own origin matches the login, wherever it is embedded. `isSameOrigin(_:_:)` with the tab's address
    /// then tells whether to say “In a frame of example.com”.
    func match(itemURL: URL, rule: VaultURLMatch, page: URL) -> VaultURLMatchResult {
        guard let item = VaultURLAddress(itemURL), let target = VaultURLAddress(page),
              item.scheme == "http" || target.scheme == "https"
        else {
            return .noMatch
        }
        let matches = switch rule {
        case .site:
            site(of: item) == site(of: target)
        case .host:
            item.host == target.host && item.port == target.port
        case .page:
            item.host == target.host && item.port == target.port && item.path == target.path
        }
        guard matches else {
            return .noMatch
        }
        return target.scheme == "https" ? .match : .insecureMatch
    }

    /// The best result over the addresses of a login as kept in `urls`, each read by `normalizedItemURL(_:)`; an
    /// address that isn't one is skipped.
    func match(itemURLs: [String], rule: VaultURLMatch, page: URL) -> VaultURLMatchResult {
        var best = VaultURLMatchResult.noMatch
        for text in itemURLs {
            guard let itemURL = Self.normalizedItemURL(text) else {
                continue
            }
            let result = match(itemURL: itemURL, rule: rule, page: page)
            if result == .match {
                return result
            }
            if result == .insecureMatch {
                best = result
            }
        }
        return best
    }

    /// The site of `url` in the sense of § 8.2, what “Never for this site” is kept under: its registrable domain, or
    /// its whole host for an IP address, `localhost`, a single label or a public suffix. Nil unless `url` is an `http`
    /// or `https` address with a host.
    func site(of url: URL) -> String? {
        VaultURLAddress(url).map { site(of: $0) }
    }

    private func site(of address: VaultURLAddress) -> String {
        if address.isIPAddress {
            return address.host
        }
        return publicSuffixList.registrableDomain(of: address.host) ?? address.host
    }

    /// True if `lhs` and `rhs` are `http` or `https` addresses of the same origin: scheme, host and port, a scheme's
    /// default port counting as none.
    static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = VaultURLAddress(lhs), let right = VaultURLAddress(rhs) else {
            return false
        }
        return left.scheme == right.scheme && left.host == right.host && left.port == right.port
    }
}

/// An `http` or `https` address reduced to what the rules of `VaultURLMatcher` compare.
private nonisolated struct VaultURLAddress {
    private static let defaultPorts = ["http": 80, "https": 443]

    /// “http” or “https”.
    let scheme: String
    /// The canonical host (`PublicSuffixList.canonicalHost(_:)`), or an IPv6 address lowercased, without brackets.
    let host: String
    /// The port, nil when it is absent or the default of the scheme.
    let port: Int?
    /// The path, percent-decoded, without its final slash (empty for the root).
    let path: String

    /// Nil unless `url` is `http` or `https` and has a valid host.
    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), let defaultPort = Self.defaultPorts[scheme],
              let rawHost = url.host(percentEncoded: false)?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              let host = rawHost.contains(":") ? rawHost.lowercased() : PublicSuffixList.canonicalHost(rawHost)
        else {
            return nil
        }
        self.scheme = scheme
        self.host = host
        port = url.port == defaultPort ? nil : url.port
        var path = url.path(percentEncoded: false)
        if path.hasSuffix("/") {
            path.removeLast()
        }
        self.path = path
    }

    /// True for an IPv6 address, or an IPv4 one: a host whose last label is a number, as the URL standard reads it
    /// (“192.168.0.1”, “0x7f.1”).
    var isIPAddress: Bool {
        guard !host.contains(":") else {
            return true
        }
        guard let last = host.split(separator: ".").last else {
            return false
        }
        if last.hasPrefix("0x") {
            return last.dropFirst(2).allSatisfy(\.isHexDigit)
        }
        return last.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
