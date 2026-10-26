import Foundation
@testable import Matcha
import Testing
import WebKit

/// Icons read from inside the page (`FaviconPageReader`): an SVG comes back drawn as a bitmap by WebKit, a bitmap as is.
@MainActor
@Suite(.webKit)
struct FaviconPageReaderTests {
    private func loadedWebView() async throws -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), configuration: WKWebViewConfiguration())
        webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "about:blank"))
        try await waitUntil { !webView.isLoading && webView.url != nil }
        return webView
    }

    @Test func `an SVG icon is drawn into a bitmap the app can decode`() async throws {
        let webView = try await loadedWebView()
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect width="16" height="16" fill="#34C759"/></svg>"##
        let url = try #require(URL(string: "data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())"))
        let data = try #require(
            await FaviconPageReader.read([url], from: webView, maximumSize: FaviconService.maximumSize),
            "The page drew no bitmap of the SVG icon",
        )
        let decoded = try #require(FaviconDecoder.decodeNow(data))
        #expect(decoded.image.width == FaviconPageReader.drawnSide)
    }

    /// An SVG icon that can't be drawn is no icon: the next one is tried.
    @Test func `an SVG icon that can't be drawn leaves its place to the next one`() async throws {
        let webView = try await loadedWebView()
        let broken = try #require(URL(string: "data:image/svg+xml;base64,\(Data("<svg pas une image".utf8).base64EncodedString())"))
        let png = try #require(AvatarImage.initials("M", color: "#0A84FF"))
        let url = try #require(URL(string: "data:image/png;base64,\(png.base64EncodedString())"))
        #expect(await FaviconPageReader.read([broken, url], from: webView, maximumSize: FaviconService.maximumSize) == png)
        #expect(await FaviconPageReader.read([broken], from: webView, maximumSize: FaviconService.maximumSize) == nil)
    }

    @Test func `the first icon that loads wins, a bitmap comes back as is`() async throws {
        let webView = try await loadedWebView()
        let missing = try #require(URL(string: "data:image/png;base64,"))
        let png = try #require(AvatarImage.initials("M", color: "#0A84FF"))
        let url = try #require(URL(string: "data:image/png;base64,\(png.base64EncodedString())"))
        #expect(await FaviconPageReader.read([missing, url], from: webView, maximumSize: FaviconService.maximumSize) == png)
    }
}
