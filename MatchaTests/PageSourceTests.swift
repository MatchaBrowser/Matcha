import Foundation
@testable import Matcha
import Testing
import WebKit

/// “View Page Source”: viewer address, reading the text, a page that shows it without running anything, and only for
/// the viewers opened by the app (audit W1).
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
        let file = try Self.temporaryPage("<p>Bonjour</p>\n<b>gras</b>")
        defer { try? FileManager.default.removeItem(at: file) }
        let webView = WKWebView(frame: .zero, configuration: WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent()))
        let viewer = try #require(PageSource.viewerURL(for: file))
        PageSourceSchemeHandler.shared.authorize(viewer, in: webView.configuration.websiteDataStore)
        webView.load(URLRequest(url: viewer))
        try await waitUntil { webView.title?.hasPrefix("Source") == true && !webView.isLoading }
        let text = try await Self.text(of: webView)
        #expect(text.contains("<p>Bonjour</p>"))
        #expect(text.contains("<b>gras</b>"))
    }

    @Test func `a viewer address the app didn't open is neither fetched nor read`() async throws {
        let secret = "secret-\(UUID().uuidString)"
        let file = try Self.temporaryPage(secret)
        defer { try? FileManager.default.removeItem(at: file) }
        let webView = WKWebView(frame: .zero, configuration: WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent()))
        let viewer = try #require(PageSource.viewerURL(for: file))
        webView.load(URLRequest(url: viewer))
        try await waitUntil { webView.title?.hasPrefix("Source") == true && !webView.isLoading }
        let text = try await Self.text(of: webView)
        #expect(!text.contains(secret))
        #expect(text.contains("View Page Source"))
    }

    @Test func `an authorized viewer is only served to the profile that opened it`() throws {
        let viewer = try #require(URL(string: "matcha-source:https://example.com/compte"))
        let store = WKWebsiteDataStore.nonPersistent()
        PageSourceSchemeHandler.shared.authorize(viewer, in: store)
        #expect(PageSourceSchemeHandler.shared.isAuthorized(viewer, in: store))
        #expect(!PageSourceSchemeHandler.shared.isAuthorized(viewer, in: .nonPersistent()))
        #expect(try !PageSourceSchemeHandler.shared.isAuthorized(
            #require(URL(string: "matcha-source:https://example.com/autre")),
            in: store,
        ))
    }

    @Test func `a page can't show an authorized viewer in a frame`() async throws {
        let secret = "secret-\(UUID().uuidString)"
        let file = try Self.temporaryPage(secret)
        defer { try? FileManager.default.removeItem(at: file) }
        let configuration = TestPages.configuration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let viewer = try #require(PageSource.viewerURL(for: file))
        PageSourceSchemeHandler.shared.authorize(viewer, in: webView.configuration.websiteDataStore)
        webView.load(URLRequest(url: TestPages.url("cadre", body: "<iframe src=\"\(viewer.absoluteString)\"></iframe>")))
        try await waitUntil { webView.title == "cadre" && !webView.isLoading }
        let archive = try await Self.archive(of: webView)
        #expect(archive.range(of: Data(secret.utf8)) == nil)
    }

    @Test func `a restored viewer tab stays readable`() throws {
        let viewer = try #require(URL(string: "matcha-source:https://example.com/restaure-\(UUID().uuidString)"))
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
        let tab = BrowserTab(restoring: StoredTab(id: UUID(), url: viewer, lastActivity: .now), configuration: configuration)
        #expect(PageSourceSchemeHandler.shared.isAuthorized(viewer, in: tab.configuration.websiteDataStore))
    }

    @Test func `only regular files of a reasonable size are read`() throws {
        #expect(throws: PageSourceLoader.Failure.notAFile) {
            try PageSourceLoader.readFile(URL(filePath: "/dev/zero"))
        }
        let large = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: large) }
        #expect(FileManager.default.createFile(atPath: large.path, contents: nil))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(PageSourceLoader.maximumSize + 1))
        try handle.close()
        #expect(throws: PageSourceLoader.Failure.tooLarge) {
            try PageSourceLoader.readFile(large)
        }
    }

    private static func temporaryPage(_ html: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).html")
        try Data(html.utf8).write(to: file)
        return file
    }

    /// Text of the displayed page, read from its web archive: the viewer runs no script, not even the app's.
    private static func text(of webView: WKWebView) async throws -> String {
        let data = try await archive(of: webView)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let main = plist?["WebMainResource"] as? [String: Any]
        let html = (main?["WebResourceData"] as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return html.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func archive(of webView: WKWebView) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            webView.createWebArchiveData { continuation.resume(with: $0) }
        }
    }
}
