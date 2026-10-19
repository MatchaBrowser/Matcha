import Foundation
@testable import Matcha
import Testing
import WebKit

/// “View Page Source”: viewer address, reading the text, a page that shows it without running anything.
@MainActor
struct PageSourceTests {
    @Test func `the viewer address leads back to its page`() throws {
        let page = try #require(URL(string: "https://example.com/a/b?x=1&y=é#haut"))
        let viewer = try #require(PageSource.viewerURL(for: page))
        #expect(viewer.scheme == "matcha-source")
        #expect(PageSource.pageURL(fromViewer: viewer) == page)
        #expect(PageSource.viewerURL(for: URL(string: "about:blank")) == nil)
        #expect(PageSource.viewerURL(for: nil) == nil)
        #expect(try PageSource.pageURL(fromViewer: #require(URL(string: "matcha-source:javascript:alert(1)"))) == nil)
    }

    @Test func `text is read in the charset of the response`() {
        let latin = Data([0x63, 0x61, 0x66, 0xE9])
        #expect(PageSource.text(of: latin, textEncodingName: "iso-8859-1") == "café")
        #expect(PageSource.text(of: Data("café".utf8), textEncodingName: nil) == "café")
        #expect(PageSource.text(of: latin, textEncodingName: "inconnu") == "café")
    }

    @Test func `the viewer escapes the source and numbers its lines`() {
        let html = PageSource.viewerHTML(source: "<h1>Titre</h1>\n\n<script>alert(\"x\")</script>", title: "Source <de> la page")
        #expect(html.contains("<li>&lt;h1&gt;Titre&lt;/h1&gt;</li>"))
        #expect(html.contains("<li> </li>"))
        #expect(html.contains("<li>&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;</li>"))
        #expect(!html.contains("<script>"))
        #expect(html.contains("<title>Source &lt;de&gt; la page</title>"))
        #expect(html.components(separatedBy: "<li>").count - 1 == 3)
    }

    @Test func `a viewer tab shows the source of a local page`() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("<p>Bonjour</p>\n<b>gras</b>".utf8).write(to: file)
        let webView = WKWebView(frame: .zero, configuration: WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent()))
        let viewer = try #require(PageSource.viewerURL(for: file))
        webView.load(URLRequest(url: viewer))
        try await waitUntil { webView.title?.hasPrefix("Source") == true && !webView.isLoading }
        let lines = try await webView.evaluateJavaScript("[...document.querySelectorAll('li')].map(li => li.textContent)") as? [String]
        #expect(lines == ["<p>Bonjour</p>", "<b>gras</b>"])
    }
}
