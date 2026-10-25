import Foundation
@testable import Matcha
import Testing

/// Origin of a page, the key of permission decisions (task 5.2).
struct SiteOriginTests {
    @Test func `scheme and host are lowercased and the default port is dropped`() throws {
        let origin = try #require(SiteOrigin(scheme: "HTTPS", host: "Meet.Example.COM.", port: 443))
        #expect(origin.key == "https://meet.example.com")
        #expect(origin.port == nil)
        // WebKit gives 0 for the default port.
        #expect(SiteOrigin(scheme: "https", host: "meet.example.com", port: 0) == origin)
        #expect(SiteOrigin(scheme: "http", host: "example.com", port: 80)?.key == "http://example.com")
    }

    @Test func `another port is kept and names the origin`() throws {
        let origin = try #require(SiteOrigin(scheme: "http", host: "localhost", port: 8080))
        #expect(origin.key == "http://localhost:8080")
        #expect(origin.displayHost == "localhost:8080")
        // Outside https, the scheme is shown: two origins of the same host stay distinct.
        #expect(origin.displayName == "http://localhost:8080")
        #expect(origin != SiteOrigin(scheme: "https", host: "localhost", port: 8080))
        #expect(SiteOrigin(scheme: "https", host: "example.com", port: 443) != SiteOrigin(scheme: "https", host: "example.com", port: 8443))
    }

    @Test func `origin of an address ignores its path, query and fragment`() throws {
        let url = try #require(URL(string: "https://www.Example.com:8443/salle/42?nom=moi#vue"))
        let origin = try #require(SiteOrigin(url: url))
        #expect(origin.key == "https://www.example.com:8443")
        #expect(origin.displayHost == "example.com:8443")
        #expect(origin.displayName == "example.com:8443")
        let other = try #require(URL(string: "https://www.example.com/autre"))
        #expect(SiteOrigin(url: other) == SiteOrigin(scheme: "https", host: "www.example.com", port: nil))
    }

    @Test(arguments: ["file:///tmp/page.html", "about:blank", "data:text/html,salut"])
    func `pages without a host have no origin`(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(SiteOrigin(url: url) == nil)
        #expect(SiteOrigin.web(of: url) == nil)
    }

    @Test func `website origins are http and https only`() {
        #expect(SiteOrigin.web(of: URL(string: "https://example.com")) != nil)
        #expect(SiteOrigin.web(of: URL(string: "http://localhost:3000")) != nil)
        #expect(SiteOrigin.web(of: URL(string: "obtest://pages/page")) == nil)
        #expect(SiteOrigin.web(of: nil) == nil)
        #expect(SiteOrigin(scheme: "", host: "example.com", port: nil) == nil)
        #expect(SiteOrigin(scheme: "https", host: "", port: nil) == nil)
    }

    @Test(arguments: ["https://meet.example.com", "http://localhost:8080", "http://192.168.1.10", "http://[::1]:3000"])
    func `a saved key reads back as the same origin`(key: String) throws {
        let origin = try #require(SiteOrigin(key: key))
        #expect(origin.key == key)
        #expect(SiteOrigin(key: origin.key) == origin)
    }

    @Test func `IPv6 hosts are kept without brackets`() throws {
        let fromWebKit = try #require(SiteOrigin(scheme: "http", host: "[::1]", port: 3000))
        let url = try #require(URL(string: "http://[::1]:3000/"))
        let fromURL = try #require(SiteOrigin(url: url))
        #expect(fromWebKit == fromURL)
        #expect(fromWebKit.host == "::1")
        #expect(fromWebKit.displayName == "http://[::1]:3000")
    }

    /// Review WB2: what `window.isSecureContext` says of a website.
    @Test(arguments: [
        ("https://example.com", true),
        ("http://localhost:8080", true),
        ("http://app.localhost", true),
        ("http://127.0.0.1:3000", true),
        ("http://[::1]:3000", true),
        ("http://example.com", false),
        ("http://127.example.com", false),
        ("http://192.168.1.1", false),
    ])
    func `a secure context is https, or http on this Mac`(address: String, isSecure: Bool) throws {
        let origin = try #require(URL(string: address).flatMap(SiteOrigin.init(url:)))
        #expect(origin.isSecureContext == isSecure)
    }
}
