import Foundation
@testable import Matcha
import Testing

struct SiteDomainTests {
    private func site(_ text: String) -> String? {
        URL(string: text).flatMap(SiteDomain.site(of:))
    }

    @Test func `the last two labels make the site`() {
        #expect(site("https://www.apple.com/fr/") == "apple.com")
        #expect(site("https://mail.google.com/mail/u/0/") == "google.com")
        #expect(site("http://a.b.c.example.com:8443/page") == "example.com")
    }

    @Test func `known two label suffixes keep three labels`() {
        #expect(site("https://news.bbc.co.uk/sport") == "bbc.co.uk")
        #expect(site("https://moi.github.io/projet") == "moi.github.io")
        #expect(site("https://www.impots.gouv.fr/") == "impots.gouv.fr")
    }

    @Test func `addresses and single names are kept whole`() {
        #expect(site("http://127.0.0.1:8080/") == "127.0.0.1")
        #expect(site("http://[::1]/") == "::1")
        #expect(site("http://localhost:3000/") == "localhost")
        #expect(site("http://intranet/wiki") == "intranet")
    }

    @Test func `case and trailing dot are ignored`() {
        #expect(site("https://Apple.COM./") == "apple.com")
    }

    @Test func `pages outside the web have no site`() {
        #expect(site("file:///usr/share/doc/postfix/html/index.html") == nil)
        #expect(site("about:blank") == nil)
        #expect(site("mailto:moi@example.com") == nil)
    }

    @Test func `cross site needs two sites`() throws {
        let file = try #require(URL(string: "file:///tmp/page.html"))
        let apple = try #require(URL(string: "https://www.apple.com/"))
        let wikipedia = try #require(URL(string: "https://fr.wikipedia.org/"))
        #expect(!SiteDomain.isCrossSite(from: file, to: apple))
        #expect(!SiteDomain.isCrossSite(from: apple, to: file))
        #expect(SiteDomain.isCrossSite(from: apple, to: wikipedia))
    }

    @Test func `google mail and accounts are the same site`() throws {
        let mail = try #require(URL(string: "https://mail.google.com/mail/u/0/"))
        let accounts = try #require(URL(string: "https://accounts.google.com/ServiceLogin"))
        #expect(!SiteDomain.isCrossSite(from: mail, to: accounts))
    }
}
