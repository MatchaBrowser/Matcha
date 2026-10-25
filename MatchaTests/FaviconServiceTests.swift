import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// Tests without network: the icons are served as `data:` URLs.
@MainActor
struct FaviconServiceTests {
    /// 1 × 1 pixel PNG image.
    static let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    static let pngURL = URL(string: "data:image/png;base64,\(pngBase64)")!

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FaviconServiceTests-\(UUID().uuidString)", isDirectory: true)
    private let page = URL(string: "https://www.example.test/page")!

    @Test func `downloads the icon and caches it in memory and on disk`() async {
        let service = FaviconService(directory: directory)
        let candidate = FaviconCandidate(url: Self.pngURL, rel: "icon")

        let image = await service.fetchIcon(forPage: page, candidates: [candidate])
        #expect(image != nil)
        #expect(service.cachedIcon(forHost: "www.example.test") === image)
        await service.waitForDisk()
        // Review SV3: a PNG of the decoded icon, not the downloaded bytes.
        let file = directory.appendingPathComponent("www.example.test")
        #expect((try? Data(contentsOf: file))?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))

        let reloaded = FaviconService(directory: directory)
        #expect(reloaded.cachedIcon(forHost: "www.example.test") == nil)
        #expect(await reloaded.loadCachedIcon(forHost: "www.example.test") != nil)
        #expect(reloaded.cachedIcon(forHost: "www.example.test") != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func `a tab restored without its page shows the icon kept on disk`() async throws {
        let cached = FaviconService(directory: directory)
        _ = await cached.fetchIcon(forPage: page, candidates: [FaviconCandidate(url: Self.pngURL, rel: "icon")])
        await cached.waitForDisk()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A new launch: nothing in memory, the tab is restored without a web view.
        let manager = TabManager(
            websiteDataStore: .nonPersistent(),
            services: SessionServices(favicons: FaviconService(directory: directory)),
        )
        let id = UUID()
        var layout = SidebarLayout()
        layout.setPlace(id, to: .pinned)
        manager.restore(tabs: [StoredTab(id: id, url: page, title: "Page", lastActivity: .now)], layout: layout)
        let tab = try #require(manager.tab(withID: id))
        #expect(!tab.isLoaded)
        for _ in 0 ..< 100 where tab.favicon == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(tab.favicon != nil)
    }

    @Test func `skips candidates that are not images`() async throws {
        let service = FaviconService(directory: nil)
        let text = try FaviconCandidate(url: #require(URL(string: "data:text/plain,bonjour")), rel: "icon", sizes: "512x512")
        let png = FaviconCandidate(url: Self.pngURL, rel: "icon", sizes: "16x16")
        #expect(await service.fetchIcon(forPage: page, candidates: [text, png]) != nil)
    }

    @Test func `unknown host has no cached icon`() async {
        #expect(await FaviconService(directory: directory).loadCachedIcon(forHost: "inconnu.test") == nil)
    }

    /// Audit W8: a page can't make the app buffer an icon of any size.
    @Test func `an icon larger than the limit is not kept`() async throws {
        let service = FaviconService(directory: nil)
        let small = Data(count: 10).base64EncodedString()
        let large = Data(count: FaviconService.maximumSize + 1).base64EncodedString()
        #expect(try await service.download(#require(URL(string: "data:image/png;base64,\(small)")))?.count == 10)
        #expect(try await service.download(#require(URL(string: "data:image/png;base64,\(large)"))) == nil)
    }

    @Test func `icon requests carry no cookies`() {
        let configuration = FaviconService.makeConfiguration()
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.timeoutIntervalForResource == 15)
    }

    @Test func `extracts declared icons with absolute addresses`() async throws {
        let tab = BrowserTab(configuration: TestPages.configuration())
        let links = """
        <link rel='icon' href='/a.png' sizes='32x32'><link rel='apple-touch-icon' href='touch.png'>\
        <link rel='stylesheet' href='s.css'>
        """
        tab.load(TestPages.url("icones", body: links))
        try await waitUntil { tab.title == "icones" && !tab.isLoading }

        let candidates = await FaviconCandidate.extract(from: tab.loadedWebView)
        #expect(candidates.map(\.url.absoluteString) == ["obtest://pages/a.png", "obtest://pages/touch.png"])
        #expect(candidates.first?.sizes == "32x32")
        #expect(candidates.last?.rel == "apple-touch-icon")
    }

    @Test func `tab gets its icon after loading`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent(), services: SessionServices(favicons: FaviconService(directory: nil)))
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("avec-icone", body: "<link rel='icon' href='\(Self.pngURL.absoluteString)'>"))
        // Loading, reading the icons in the page, then downloading: 0.2 s alone, but nearly 10 s when the whole
        // suite runs (web views and main thread shared), already before task 5.8.
        try await waitUntil(timeout: .seconds(30)) { tab.favicon != nil }
    }

    @Test func `an icon that could not be found is retried on the next load`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent(), services: SessionServices(favicons: FaviconService(directory: nil)))
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("sans-icone"))
        try await waitUntil { tab.title == "sans-icone" && !tab.isLoading }
        // Lets the first search, which finds nothing, finish: a search still in progress would be picked up by the
        // next load, without the icons of its page (slow when many web views are running).
        try await Task.sleep(for: .milliseconds(300))
        try await waitUntil { !manager.faviconService.isRefreshingIcon(forHost: "pages") }
        #expect(tab.favicon == nil)

        tab.load(TestPages.url("avec-icone", body: "<link rel='icon' href='\(Self.pngURL.absoluteString)'>"))
        try await waitUntil { tab.favicon != nil }
    }
}
