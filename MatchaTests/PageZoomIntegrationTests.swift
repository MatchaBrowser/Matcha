import Foundation
@testable import Matcha
import Testing
import WebKit

/// Page zoom with real web views (task 5.4): the site's zoom applied to each new document (tab, Peek, mini window),
/// spread to the site's other open pages, forgotten at 100%. Simulated web pages (`loadSimulatedRequest`), without
/// network.
@MainActor
@Suite(.webKit)
struct PageZoomIntegrationTests {
    private let store = SiteZoomStore(defaults: nil)
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    init() {
        manager.siteZooms = store
    }

    /// Selected tab, at the top of today tabs, on the simulated web page `address`.
    private func open(_ address: String) async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        try await load(address, in: tab)
        return tab
    }

    /// Loads into `tab` a simulated page at `address`, whose title is its path.
    private func load(_ address: String, in tab: BrowserTab) async throws {
        let url = try #require(URL(string: address))
        let title = url.lastPathComponent
        tab.loadedWebView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<title>\(title)</title><p>\(title)</p>")
        try await waitUntil { tab.url == url && tab.title == title && !tab.isLoading }
    }

    private func zoom(of tab: BrowserTab) -> Double {
        tab.loadedWebView.pageZoom
    }

    @Test func `a new page takes the zoom of its site`() async throws {
        store.setLevel(1.25, forSite: "example.com")
        let tab = try await open("https://www.example.com/premiere")
        #expect(tab.pageZoom == 1.25)
        #expect(zoom(of: tab) == 1.25)

        // Another site: 100%; back on the site: its zoom.
        try await load("https://apple.com/autre", in: tab)
        #expect(zoom(of: tab) == 1)
        try await load("https://example.com/retour", in: tab)
        #expect(zoom(of: tab) == 1.25)
    }

    @Test func `zooming a page zooms the open pages of its site only`() async throws {
        let first = try await open("https://example.com/a")
        let second = try await open("https://docs.example.com/b")
        let other = try await open("https://apple.com/c")

        #expect(PageZoom.apply(.zoomIn, to: first, siteZooms: store) == 1.15)
        #expect(PageZoom.apply(.zoomIn, to: second, siteZooms: store) == 1.25)
        #expect(zoom(of: first) == 1.25)
        #expect(zoom(of: second) == 1.25)
        #expect(zoom(of: other) == 1)
        #expect(store.levels == ["example.com": 1.25])

        #expect(PageZoom.apply(.zoomOut, to: other, siteZooms: store) == 0.85)
        #expect(zoom(of: first) == 1.25)

        // Actual size: the site is forgotten, all its pages go back to 100%.
        #expect(PageZoom.apply(.actualSize, to: second, siteZooms: store) == 1)
        #expect(zoom(of: first) == 1)
        #expect(zoom(of: second) == 1)
        #expect(store.levels == ["apple.com": 0.85])
        #expect(!PageZoom.canApply(.actualSize, to: first))
        #expect(PageZoom.apply(.actualSize, to: first, siteZooms: store) == nil)
    }

    /// Click on the zoom badge: like ⌘0, the site is forgotten and all its open pages go back to 100%.
    @Test func `the zoom badge brings the site back to 100 percent`() async throws {
        let first = try await open("https://example.com/badge")
        let second = try await open("https://docs.example.com/badge")
        PageZoom.apply(.zoomIn, to: first, siteZooms: store)
        #expect(ZoomBadge.isShown(for: first))
        #expect(ZoomBadge.isShown(for: second))

        ZoomBadge.reset(second, siteZooms: store)
        #expect(!ZoomBadge.isShown(for: first))
        #expect(!ZoomBadge.isShown(for: second))
        #expect(zoom(of: first) == 1)
        #expect(store.levels.isEmpty)
    }

    @Test func `the bounds stop the zoom`() async throws {
        let tab = try await open("https://example.com/bornes")
        store.setLevel(3, forSite: "example.com")
        #expect(zoom(of: tab) == 3)
        #expect(!PageZoom.canApply(.zoomIn, to: tab))
        #expect(PageZoom.apply(.zoomIn, to: tab, siteZooms: store) == nil)
        #expect(PageZoom.canApply(.zoomOut, to: tab))
    }

    @Test func `an unloaded tab cannot zoom and comes back at 100 percent`() {
        let tab = BrowserTab(configuration: TestPages.configuration())
        #expect(!PageZoom.canApply(.zoomIn, to: tab))
        #expect(PageZoom.apply(.zoomIn, to: tab, siteZooms: store) == nil)

        tab.setPageZoom(1.5)
        tab.unload(resettingTo: nil, title: nil)
        #expect(tab.pageZoom == 1)
    }

    @Test func `without a store the page keeps its own zoom`() async throws {
        let tab = try await open("https://example.com/seule")
        #expect(PageZoom.apply(.zoomIn, to: tab, siteZooms: nil) == 1.15)
        #expect(zoom(of: tab) == 1.15)
        #expect(store.levels.isEmpty)
    }

    @Test func `the peek takes the zoom of its site`() async throws {
        store.setLevel(1.5, forSite: "example.com")
        let source = try await open("https://apple.com/source")
        let peek = try #require(manager.openPeek(TestPages.url("apercu"), from: source))
        try await waitUntil { peek.tab.title == "apercu" && !peek.tab.isLoading }
        #expect(zoom(of: peek.tab) == 1)

        try await load("https://example.com/apercu", in: peek.tab)
        #expect(zoom(of: peek.tab) == 1.5)
        // A change to the site reaches Peek.
        store.setLevel(2, forSite: "example.com")
        #expect(zoom(of: peek.tab) == 2)
        manager.closePeek()
    }

    @Test func `a mini window page takes the zoom of local files`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let miniWindows = MiniWindowManager.forTests(session: session)
        session.siteZooms.setLevel(1.75, forSite: SiteZoomKey.localFiles)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zoom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("locale.html")
        try Data("<title>locale</title><p>Page locale</p>".utf8).write(to: file)

        let mini = miniWindows.openNew(loading: file, source: .link)
        defer { mini.close() }
        try await waitUntil { mini.tab.title == "locale" && !mini.tab.isLoading }
        #expect(mini.tab.pageZoom == 1.75)
        #expect(mini.tab.loadedWebView.pageZoom == 1.75)
    }
}
