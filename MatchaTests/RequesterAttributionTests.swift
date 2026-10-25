import AppKit
@testable import Matcha
import Testing
import WebKit

/// Review WB1: a request to open an app or to download is the asking document's, never that of a frame inside it
/// passed off as the page, nor of the address being loaded.
@MainActor
struct RequesterAttributionTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let probe = FrameProbe()
    private var opened: [URL] = []

    /// Frames that called `probe`, to run a script in them.
    private final class FrameProbe: NSObject, WKScriptMessageHandler {
        var frames: [WKFrameInfo] = []

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            frames.append(message.frameInfo)
        }
    }

    /// Files WebKit can't display: every load becomes a download.
    private final class AttachmentPages: NSObject, WKURLSchemeHandler {
        static let scheme = "obtest-files"

        func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url else { return }
            let response = URLResponse(url: url, mimeType: "application/octet-stream", expectedContentLength: 4, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data([1, 2, 3, 4]))
            urlSchemeTask.didFinish()
        }

        func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
    }

    init() {
        manager.coordinator.openExternally = { _ in true }
        manager.coordinator.applicationForURL = { _ in URL(filePath: "/System/Applications/Mail.app") }
    }

    /// A page of `TestPages` on `host`, whose title is `name`.
    private static func url(host: String, _ name: String, body: String = "") throws -> URL {
        var components = try #require(URLComponents(url: TestPages.url(name, body: body), resolvingAgainstBaseURL: false))
        components.host = host
        return try #require(components.url)
    }

    private func openPage(body: String = "") -> BrowserTab {
        let configuration = TestPages.configuration()
        configuration.setURLSchemeHandler(SilentPages(), forURLScheme: SilentPages.scheme)
        configuration.setURLSchemeHandler(AttachmentPages(), forURLScheme: AttachmentPages.scheme)
        configuration.userContentController.add(probe, name: "probe")
        let page = manager.insertTab(configuration: configuration, after: nil, select: true)
        page.load(TestPages.url("top", body: body))
        return page
    }

    @Test func `a frame of another site can't open an app, even through a new window`() async throws {
        let frame = try Self.url(host: "ads", "frame", body: #"<script>webkit.messageHandlers.probe.postMessage("")</script>"#)
        let page = openPage(body: "<iframe src='\(frame.absoluteString)'></iframe>")
        try await waitUntil { probe.frames.contains { !$0.isMainFrame } }
        let adFrame = try #require(probe.frames.first { !$0.isMainFrame })
        #expect(adFrame.securityOrigin.host == "ads")

        // Run as after a click in the frame: WebKit lets it open a window, whose load asks for the app.
        _ = try await page.loadedWebView.evaluateJavaScript("window.open('mailto:ad@example.com'); true", in: adFrame, contentWorld: .page)
        // Then the page itself asks: its request waits, in its name; the frame's was refused.
        _ = try await page.loadedWebView.evaluateJavaScript("window.open('zoommtg://zoom.us/join'); true")
        try await waitUntil { !waiting.isEmpty }
        #expect(waiting.map(\.action) == [.openApp(scheme: "zoommtg")])
        #expect(waiting.first?.origin?.host == "pages")
    }

    /// Requests waiting in the banners of the tabs (a window opened by the page has its own).
    private var waiting: [SiteActionRequest] {
        manager.tabs.compactMap(\.permissionPrompts.currentAction)
    }

    @Test func `a request made while another site loads names the page on screen`() async throws {
        let script = "location = '\(SilentPages.scheme)://zoom/j/1'; setTimeout(() => { location = 'zoommtg://zoom.us/join' }, 100)"
        let page = openPage(body: "<script>\(script)</script>")
        try await waitUntil { page.permissionPrompts.currentAction != nil }
        #expect(page.permissionPrompts.currentAction?.origin?.host == "pages")
    }

    @Test func `a file's download is asked for by the page on screen, not by the file's server`() async throws {
        // The first download goes without asking; the second asks, in the page's name.
        let first = "\(AttachmentPages.scheme)://cdn/a.bin"
        let second = "\(AttachmentPages.scheme)://cdn/b.bin"
        let page = openPage()
        try await waitUntil { page.title == "top" && !page.isLoading }
        _ = try await page.loadedWebView.evaluateJavaScript("location = '\(first)'; true")
        try await waitUntil { page.pageDownloads.started == 1 }
        _ = try await page.loadedWebView.evaluateJavaScript("location = '\(second)'; true")
        try await waitUntil { page.permissionPrompts.currentAction != nil }
        #expect(page.permissionPrompts.currentAction?.action == .downloadFiles)
        #expect(page.permissionPrompts.currentAction?.origin?.host == "pages")
        page.permissionPrompts.answerAction(.decline)
    }
}
