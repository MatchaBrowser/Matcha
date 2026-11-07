import Foundation
@testable import Matcha
import Testing

/// Key of a page's note and links to a page or a site (task 12.1, `SYNC.md` § 2.10).
struct NotePageKeyTests {
    private func key(_ address: String) throws -> String? {
        try NotePageKey.key(for: #require(URL(string: address)))
    }

    @Test func `the key keeps host, path and query, without scheme or fragment`() throws {
        #expect(try key("https://Example.com/Path/Page?b=2&a=1#section") == "example.com/Path/Page?a=1&b=2")
        #expect(try key("http://example.com/Path/Page?a=1&b=2") == "example.com/Path/Page?a=1&b=2")
        #expect(try key("https://user:secret@example.com/a") == "example.com/a")
    }

    @Test func `the root and a final slash give the same key`() throws {
        #expect(try key("https://example.com") == "example.com/")
        #expect(try key("https://example.com/") == "example.com/")
        #expect(try key("https://example.com/docs/") == key("https://example.com/docs"))
        #expect(try key("https://example.com/docs//") == "example.com/docs")
    }

    @Test func `the default port is left out, another one kept`() throws {
        #expect(try key("https://example.com:443/a") == "example.com/a")
        #expect(try key("http://example.com:80/a") == "example.com/a")
        #expect(try key("http://localhost:8080/a") == "localhost:8080/a")
        #expect(try key("http://[::1]:3000/a") == "[::1]:3000/a")
    }

    @Test func `tracking parameters are left out`() throws {
        #expect(try key("https://example.com/a?utm_source=news&id=3&fbclid=x&UTM_Medium=mail") == "example.com/a?id=3")
        #expect(try key("https://example.com/a?utm_source=news&gclid=1") == "example.com/a")
        #expect(try key("https://www.youtube.com/watch?v=abc&si=share") == "www.youtube.com/watch?v=abc")
    }

    @Test func `parameters are sorted by name, equal names keep their order`() throws {
        #expect(try key("https://example.com/s?tag=b&q=x&tag=a&flag") == "example.com/s?flag&q=x&tag=b&tag=a")
        #expect(try key("https://example.com/s?q=caf%C3%A9") == "example.com/s?q=caf%C3%A9")
    }

    @Test func `www is kept, as in the origins`() throws {
        #expect(try key("https://www.example.com/a") != key("https://example.com/a"))
    }

    @Test func `pages outside the web have no key`() throws {
        #expect(try key("file:///Users/me/page.html") == nil)
        #expect(try key("about:blank") == nil)
        #expect(try key("data:text/html,hello") == nil)
    }

    // MARK: Links

    @Test func `a link to a site uses the site of the zooms`() throws {
        let url = try #require(URL(string: "https://mail.google.com/mail/u/0/#inbox"))
        let site = try #require(NoteLink(url: url, scope: .site, title: "Inbox"))
        #expect(site.key == "google.com")
        let page = try #require(NoteLink(url: url, scope: .page, title: ""))
        #expect(page.key == "mail.google.com/mail/u/0")
        #expect(page.title == nil)
        #expect(try NoteLink(url: #require(URL(string: "file:///tmp/a.html")), scope: .page, title: nil) == nil)
    }

    @Test func `a saved link is read back as it is, or not at all`() {
        let link = NoteLink(storedURL: "https://example.com/a", key: "old-rule-key", scope: "page", title: "A")
        #expect(link?.key == "old-rule-key")
        #expect(link?.scope == .page)
        #expect(NoteLink(storedURL: "https://example.com/a", key: "k", scope: "folder", title: nil) == nil)
        #expect(NoteLink(storedURL: "ftp://example.com/a", key: "k", scope: "page", title: nil) == nil)
        #expect(NoteLink(storedURL: "https://example.com/a", key: "", scope: "site", title: nil) == nil)
        #expect(NoteLink(storedURL: nil, key: "k", scope: "site", title: nil) == nil)
    }

    @Test func `a note record keeps its link`() throws {
        let url = try #require(URL(string: "https://example.com/a?utm_source=x"))
        let link = try #require(NoteLink(url: url, scope: .page, title: "A"))
        let record = NoteRecord(profileID: nil, link: link)
        #expect(record.linkKey == "example.com/a")
        #expect(record.linkScopeValue == "page")
        #expect(record.link == link)
        record.link = nil
        #expect(record.linkURL == nil && record.linkKey == nil && record.linkScopeValue == nil && record.linkTitle == nil)
    }
}
