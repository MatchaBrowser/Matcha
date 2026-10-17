import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// Tests sans réseau : les icônes sont servies en URL `data:`.
@MainActor
struct FaviconServiceTests {
    /// Image PNG de 1 × 1 pixel.
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

        let reloaded = FaviconService(directory: directory)
        #expect(reloaded.cachedIcon(forHost: "www.example.test") != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func `skips candidates that are not images`() async throws {
        let service = FaviconService(directory: nil)
        let text = try FaviconCandidate(url: #require(URL(string: "data:text/plain,bonjour")), rel: "icon", sizes: "512x512")
        let png = FaviconCandidate(url: Self.pngURL, rel: "icon", sizes: "16x16")
        #expect(await service.fetchIcon(forPage: page, candidates: [text, png]) != nil)
    }

    @Test func `unknown host has no cached icon`() {
        #expect(FaviconService(directory: directory).cachedIcon(forHost: "inconnu.test") == nil)
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
        let manager = TabManager(websiteDataStore: .nonPersistent(), faviconService: FaviconService(directory: nil))
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("avec-icone", body: "<link rel='icon' href='\(Self.pngURL.absoluteString)'>"))
        try await waitUntil { tab.favicon != nil }
    }

    @Test func `an icon that could not be found is retried on the next load`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent(), faviconService: FaviconService(directory: nil))
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("sans-icone"))
        try await waitUntil { tab.title == "sans-icone" && !tab.isLoading }
        // Laisse la première recherche, infructueuse, se terminer.
        try await Task.sleep(for: .milliseconds(300))
        #expect(tab.favicon == nil)

        tab.load(TestPages.url("avec-icone", body: "<link rel='icon' href='\(Self.pngURL.absoluteString)'>"))
        try await waitUntil { tab.favicon != nil }
    }
}
