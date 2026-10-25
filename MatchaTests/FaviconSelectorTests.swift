import Foundation
@testable import Matcha
import Testing

struct FaviconSelectorTests {
    private let page = URL(string: "https://www.example.com/articles/1?x=2#haut")!

    private func candidate(_ path: String, rel: String = "icon", sizes: String = "", type: String = "") -> FaviconCandidate {
        FaviconCandidate(url: URL(string: path, relativeTo: page)!.absoluteURL, rel: rel, sizes: sizes, type: type)
    }

    @Test func `largest icon comes first and favicon ico last`() {
        let candidates = [
            candidate("/small.png", sizes: "16x16"),
            candidate("/touch.png", rel: "apple-touch-icon"),
            candidate("/big.png", sizes: "16x16 192x192"),
            candidate("/unknown.ico"),
        ]
        let urls = FaviconSelector.urlsToTry(candidates: candidates, pageURL: page).map(\.absoluteString)
        #expect(urls == [
            "https://www.example.com/big.png",
            "https://www.example.com/touch.png",
            "https://www.example.com/small.png",
            "https://www.example.com/unknown.ico",
            "https://www.example.com/favicon.ico",
        ])
    }

    /// Review SV2: a page that declares many icons gets only `maximumURLs` tries, `/favicon.ico` last.
    @Test func `at most eight addresses are tried`() {
        let candidates = (1 ... 30).map { candidate("/icon-\($0).png", sizes: "\($0)x\($0)") }
        let urls = FaviconSelector.urlsToTry(candidates: candidates, pageURL: page).map(\.absoluteString)
        #expect(urls.count == FaviconSelector.maximumURLs)
        #expect(urls.first == "https://www.example.com/icon-30.png")
        #expect(urls.last == "https://www.example.com/favicon.ico")
    }

    @Test func `vector icons rank as scalable`() {
        let svg = candidate("/icon.svg", type: "image/svg+xml")
        let any = candidate("/icon-any.png", sizes: "any")
        let png = candidate("/icon.png", sizes: "512x512")
        let urls = FaviconSelector.urlsToTry(candidates: [png, svg, any], pageURL: page)
        #expect(urls.prefix(3) == [svg.url, any.url, png.url])
    }

    @Test func `equal sizes keep the page order`() {
        let first = candidate("/a.png", sizes: "32x32")
        let second = candidate("/b.png", sizes: "32x32")
        #expect(FaviconSelector.urlsToTry(candidates: [first, second], pageURL: page).prefix(2) == [first.url, second.url])
    }

    @Test func `duplicates and unsupported schemes are dropped`() throws {
        let ico = candidate("/favicon.ico")
        let javascript = try FaviconCandidate(url: #require(URL(string: "javascript:alert(1)")), rel: "icon")
        let data = try FaviconCandidate(url: #require(URL(string: "data:image/png;base64,AA==")), rel: "icon")
        let urls = FaviconSelector.urlsToTry(candidates: [ico, javascript, data, ico], pageURL: page)
        #expect(urls == [ico.url, data.url])
    }

    /// Audit W8: an encrypted page's icon never comes unencrypted.
    @Test func `an https page never gets an http icon`() throws {
        let http = try FaviconCandidate(url: #require(URL(string: "http://cdn.example.com/icon.png")), rel: "icon", sizes: "64x64")
        let https = try FaviconCandidate(url: #require(URL(string: "https://cdn.example.com/icon.png")), rel: "icon", sizes: "32x32")
        let secure = try FaviconSelector.urlsToTry(candidates: [http, https], pageURL: #require(URL(string: "https://example.com/")))
        #expect(secure.map(\.absoluteString) == ["https://cdn.example.com/icon.png", "https://example.com/favicon.ico"])
        let plain = try FaviconSelector.urlsToTry(candidates: [http, https], pageURL: #require(URL(string: "http://example.com/")))
        #expect(plain.first?.absoluteString == "http://cdn.example.com/icon.png")
    }

    @Test func `default icon keeps scheme host and port only`() throws {
        let url = try FaviconSelector.defaultIconURL(for: #require(URL(string: "http://moi:secret@localhost:3000/app?q=1")))
        #expect(url?.absoluteString == "http://localhost:3000/favicon.ico")
    }

    @Test(arguments: ["about:blank", "file:///Users/moi/page.html", "obtest://pages/x"])
    func `no default icon outside the web`(address: String) throws {
        #expect(try FaviconSelector.defaultIconURL(for: #require(URL(string: address))) == nil)
    }

    @Test(arguments: [("16x16", 16), ("16x16 32X32 24x24", 32), ("any", 1024), ("", nil), ("nimporte", nil)] as [(String, Int?)])
    func `declared sizes are parsed`(sizes: String, expected: Int?) {
        #expect(FaviconSelector.largestDeclaredSize(sizes) == expected)
    }
}
