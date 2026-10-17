import Foundation
@testable import Matcha
import Testing
import WebKit

/// « Effacer les cookies et les données du site » (tâche 5.2) : seules les données du site visé partent.
@MainActor
struct WebsiteDataCleanerTests {
    @Test(arguments: [
        ("google.com", "mail.google.com"),
        ("google.com", "google.com"),
        ("google.com", "www.google.com"),
        ("bbc.co.uk", "news.bbc.co.uk"),
        ("localhost", "localhost"),
        ("192.168.1.10", "192.168.1.10"),
        ("Example.COM.", "shop.example.com"),
    ])
    func `records of the site and its subdomains match`(record: String, host: String) {
        #expect(WebsiteDataMatcher.matches(recordName: record, host: host))
    }

    @Test(arguments: [
        ("notgoogle.com", "google.com"),
        ("google.com", "google.com.evil.example"),
        ("mail.google.com", "google.com"),
        ("example.org", "example.com"),
        ("", "example.com"),
        ("example.com", ""),
        ("co.uk", "bbc.co.uk.example"),
    ])
    func `records of other sites never match`(record: String, host: String) {
        #expect(!WebsiteDataMatcher.matches(recordName: record, host: host))
    }

    @Test func `clearing a site removes its cookies only`() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        for domain in [".example.com", "www.example.com", ".other.org"] {
            let cookie = try #require(HTTPCookie(properties: [.domain: domain, .path: "/", .name: "session", .value: "1"]))
            await store.httpCookieStore.setCookie(cookie)
        }

        let removed = await WebsiteDataCleaner.removeData(forHost: "www.example.com", in: store)
        #expect(removed == 1)
        let remaining = await store.httpCookieStore.allCookies()
        #expect(remaining.map(\.domain) == [".other.org"])
    }
}
