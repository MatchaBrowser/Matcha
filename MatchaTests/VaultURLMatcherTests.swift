import Foundation
@testable import Matcha
import Testing

/// Which logins a page or a frame may receive (`VAULT.md` § 8.2): the rules `site`, `host` and `page`, the schemes,
/// the ports, IP addresses, `localhost`, and the addresses as typed.
struct VaultURLMatcherTests {
    /// Read once: the list has some ten thousand rules.
    private static let matcher = Result { try VaultURLMatcher(publicSuffixList: PublicSuffixList.bundled(in: .main)) }

    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    private func match(_ item: String, _ rule: VaultURLMatch, _ page: String) throws -> VaultURLMatchResult {
        let itemURL = try #require(VaultURLMatcher.normalizedItemURL(item))
        return try Self.matcher.get().match(itemURL: itemURL, rule: rule, page: url(page))
    }

    /// The examples of § 8.2, for a login saved on `https://accounts.example.co.uk/login` in `site`.
    @Test(arguments: [
        ("https://www.example.co.uk/", VaultURLMatchResult.match),
        ("https://example.co.uk:8443/", .match),
        ("http://example.co.uk/", .noMatch),
        ("https://example.com/", .noMatch),
    ] as [(String, VaultURLMatchResult)])
    func `the examples of the specification hold`(page: String, expected: VaultURLMatchResult) throws {
        #expect(try match("https://accounts.example.co.uk/login", .site, page) == expected)
    }

    @Test func `two sites of a page host are two sites`() throws {
        #expect(try match("https://bob.github.io/", .site, "https://alice.github.io/") == .noMatch)
        #expect(try match("https://bob.github.io/", .site, "https://www.bob.github.io/settings") == .match)
        // A host that is itself a public suffix is taken whole.
        #expect(try match("https://github.io/", .site, "https://alice.github.io/") == .noMatch)
        #expect(try match("https://co.uk/", .site, "https://example.co.uk/") == .noMatch)
        #expect(try match("https://github.io/", .site, "https://github.io/login") == .match)
    }

    @Test(arguments: VaultURLMatch.allCases)
    func `a login saved in https is never offered on http`(rule: VaultURLMatch) throws {
        #expect(try match("https://example.com/login", rule, "http://example.com/login") == .noMatch)
        #expect(try match("https://example.com/login", rule, "https://example.com/login") == .match)
        // Saved in http: offered on https, and on http with a warning.
        #expect(try match("http://example.com/login", rule, "https://example.com/login") == .match)
        #expect(try match("http://example.com/login", rule, "http://example.com/login") == .insecureMatch)
        #expect(try match("https://example.com/login", rule, "ftp://example.com/login") == .noMatch)
    }

    @Test func `the host rule compares host and port`() throws {
        #expect(try match("https://example.com", .host, "https://example.com:443/account") == .match)
        #expect(try match("https://example.com", .host, "https://example.com:8443/") == .noMatch)
        #expect(try match("https://example.com:8443/", .host, "https://example.com:8443/a") == .match)
        #expect(try match("https://example.com", .host, "https://www.example.com/") == .noMatch)
        #expect(try match("https://Example.COM.", .host, "https://example.com/") == .match)
        // Each scheme's default port counts as none, so the http login still matches its https page.
        #expect(try match("http://example.com", .host, "https://example.com/") == .match)
        #expect(try match("http://example.com:8080", .host, "https://example.com:8080/") == .match)
        #expect(try match("http://example.com:8080", .host, "http://example.com/") == .noMatch)
        // The site rule leaves the port out.
        #expect(try match("https://example.com", .site, "https://www.example.com:8443/") == .match)
    }

    @Test func `the page rule compares origin and path`() throws {
        let item = "https://example.com/login"
        #expect(try match(item, .page, "https://example.com/login") == .match)
        #expect(try match(item, .page, "https://example.com/login/?next=%2Fhome#form") == .match)
        #expect(try match(item, .page, "https://example.com:443/login") == .match)
        #expect(try match(item, .page, "https://example.com/login/step2") == .noMatch)
        #expect(try match(item, .page, "https://example.com/Login") == .noMatch)
        #expect(try match(item, .page, "https://example.com/") == .noMatch)
        #expect(try match(item, .page, "https://www.example.com/login") == .noMatch)
        #expect(try match(item, .page, "https://example.com:8443/login") == .noMatch)
        #expect(try match("https://example.com", .page, "https://example.com/") == .match)
        #expect(try match("example.com/café", .page, "https://example.com/caf%C3%A9/") == .match)
    }

    @Test func `IP addresses, localhost and single labels are taken whole`() throws {
        // The default rule would give both “0.1”.
        #expect(try match("http://10.0.0.1/", .site, "http://192.168.0.1/") == .noMatch)
        #expect(try match("http://192.168.0.1/", .site, "http://192.168.0.1:8080/admin") == .insecureMatch)
        #expect(try match("https://[::1]:8443/", .site, "https://[::1]/") == .match)
        #expect(try match("https://[::1]/", .site, "https://[::2]/") == .noMatch)
        #expect(try match("https://[FE80::1]/", .host, "https://[fe80::1]:443/") == .match)
        #expect(try match("localhost:3000", .site, "https://localhost:8080/") == .match)
        #expect(try match("http://localhost:3000", .host, "http://localhost:8080/") == .noMatch)
        #expect(try match("https://intranet/", .site, "https://intranet:8443/") == .match)
        #expect(try match("https://intranet/", .site, "https://wiki/") == .noMatch)
    }

    @Test func `an IDN address matches its punycode`() throws {
        #expect(try match("bücher.de/login", .site, "https://www.xn--bcher-kva.de/") == .match)
        #expect(try match("https://xn--bcher-kva.de/", .host, "https://BÜCHER.de/") == .match)
    }

    @Test(arguments: [
        ("example.com/login", "https://example.com/login"),
        ("  localhost:3000 ", "https://localhost:3000"),
        ("192.168.0.1:8080/admin", "https://192.168.0.1:8080/admin"),
        ("example.com/?next=https://other.com", "https://example.com/?next=https://other.com"),
        ("http://example.com", "http://example.com"),
        ("HTTPS://Example.com", "HTTPS://Example.com"),
    ])
    func `an address without a scheme takes https`(text: String, expected: String) {
        #expect(VaultURLMatcher.normalizedItemURL(text)?.absoluteString == expected)
    }

    @Test(arguments: [
        "",
        "   ",
        "ftp://example.com",
        "file:///etc/passwd",
        "about:blank",
        "javascript:alert(1)",
        "https://",
        "https://a..b/"
    ])
    func `only http and https addresses with a host are kept`(text: String) {
        #expect(VaultURLMatcher.normalizedItemURL(text) == nil)
    }

    @Test func `the best of a login's addresses counts`() throws {
        let matcher = try Self.matcher.get()
        let urls = ["not an address at all", "http://example.com/", "https://example.com/"]
        #expect(try matcher.match(itemURLs: urls, rule: .site, page: url("https://www.example.com/")) == .match)
        #expect(try matcher.match(itemURLs: urls, rule: .site, page: url("http://example.com/")) == .insecureMatch)
        #expect(try matcher.match(itemURLs: urls, rule: .site, page: url("https://other.com/")) == .noMatch)
        #expect(try matcher.match(itemURLs: [], rule: .site, page: url("https://example.com/")) == .noMatch)
    }

    /// A frame is matched on its own address; the tab's address only tells whether to say “In a frame of …”.
    @Test func `a frame is filled on its own origin`() throws {
        let tab = try url("https://shop.other.com/checkout")
        let loginFrame = try url("https://login.example.com/embed")
        #expect(try match("https://example.com", .site, loginFrame.absoluteString) == .match)
        #expect(try match("https://other.com", .site, loginFrame.absoluteString) == .noMatch)
        #expect(!VaultURLMatcher.isSameOrigin(loginFrame, tab))
        #expect(try VaultURLMatcher.isSameOrigin(url("https://Example.com:443/a"), url("https://example.com/b")))
        #expect(try !VaultURLMatcher.isSameOrigin(url("http://example.com/"), url("https://example.com/")))
        #expect(try !VaultURLMatcher.isSameOrigin(url("about:blank"), url("about:blank")))
    }

    @Test(arguments: [
        ("https://accounts.example.co.uk/login", "example.co.uk"),
        ("https://www.alice.github.io/", "alice.github.io"),
        ("http://10.0.0.1:8080/", "10.0.0.1"),
        ("https://[::1]/", "::1"),
        ("http://localhost:3000/", "localhost"),
        ("https://github.io/", "github.io"),
        ("about:blank", nil),
    ] as [(String, String?)])
    func `the site of an address`(address: String, site: String?) throws {
        #expect(try Self.matcher.get().site(of: #require(URL(string: address))) == site)
    }

    @Test func `the rule is stored by its name`() throws {
        let data = try JSONEncoder().encode([VaultURLMatch.site, .host, .page])
        #expect(String(bytes: data, encoding: .utf8) == #"["site","host","page"]"#)
        #expect(try JSONDecoder().decode(VaultURLMatch.self, from: Data(#""page""#.utf8)) == .page)
    }
}
