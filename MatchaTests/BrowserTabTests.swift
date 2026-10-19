@testable import Matcha
import Testing
import WebKit

@MainActor
struct BrowserTabTests {
    private func makeTab() -> BrowserTab {
        BrowserTab(configuration: WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent()))
    }

    @Test func `configures web view`() {
        let tab = makeTab()
        #expect(tab.loadedWebView.allowsBackForwardNavigationGestures)
        #expect(tab.loadedWebView.allowsMagnification)
        #expect(tab.loadedWebView.isInspectable)
    }

    @Test func `starts empty`() {
        let tab = makeTab()
        #expect(tab.title == nil || tab.title == "")
        #expect(tab.url == nil)
        #expect(!tab.isLoading)
        #expect(!tab.canGoBack)
        #expect(!tab.canGoForward)
        #expect(tab.displayTitle == String(localized: "New Tab"))
    }

    @Test func `mirrors web view state and navigates history`() async throws {
        let tab = BrowserTab(configuration: TestPages.configuration())
        let first = TestPages.url("premiere")
        let second = TestPages.url("seconde")

        tab.load(first)
        try await waitUntil { tab.title == "premiere" && !tab.isLoading }
        #expect(tab.url == first)
        #expect(tab.displayTitle == "premiere")
        #expect(!tab.canGoBack)

        tab.load(second)
        try await waitUntil { tab.title == "seconde" && !tab.isLoading }
        #expect(tab.url == second)
        #expect(tab.canGoBack)
        #expect(!tab.canGoForward)

        tab.goBack()
        try await waitUntil { tab.title == "premiere" && tab.canGoForward }
        #expect(tab.url == first)
        #expect(!tab.canGoBack)

        tab.goForward()
        try await waitUntil { tab.title == "seconde" && !tab.canGoForward }
        #expect(tab.canGoBack)
    }

    @Test func `display title falls back to host`() async throws {
        let tab = makeTab()
        tab.loadedWebView.loadHTMLString("<p>Sans titre</p>", baseURL: URL(string: "https://example.test/page"))
        try await waitUntil { tab.url != nil && !tab.isLoading }
        #expect(tab.displayTitle == "example.test")
    }

    @Test func `starts unloaded`() {
        let tab = makeTab()
        #expect(!tab.isLoaded)
        #expect(tab.webView == nil)
    }

    @Test func `unload frees the web view and reloads the given address later`() async throws {
        let tab = BrowserTab(configuration: TestPages.configuration())
        tab.load(TestPages.url("un"))
        try await waitUntil { tab.title == "un" && !tab.isLoading }
        tab.load(TestPages.url("deux"))
        try await waitUntil { tab.title == "deux" && tab.canGoBack }

        let origin = TestPages.url("origine")
        tab.unload(resettingTo: origin, title: "Origine")
        #expect(tab.webView == nil)
        #expect(tab.url == origin)
        #expect(tab.title == "Origine")
        #expect(!tab.canGoBack && !tab.isLoading)

        // The recreated view keeps the configuration (here, the test scheme) and loads the saved address.
        tab.makeWebViewIfNeeded()
        try await waitUntil { tab.title == "origine" && !tab.isLoading }
        #expect(tab.url == origin)
        #expect(!tab.canGoBack)
    }

    @Test func `has url follows the address`() async throws {
        let tab = BrowserTab(configuration: TestPages.configuration())
        #expect(!tab.hasURL)
        tab.load(TestPages.url("adresse"))
        try await waitUntil { tab.title == "adresse" && !tab.isLoading }
        #expect(tab.hasURL)

        tab.unload(resettingTo: nil, title: nil)
        #expect(!tab.hasURL)

        let stored = StoredTab(id: UUID(), url: TestPages.url("restaure"), lastActivity: .now)
        #expect(BrowserTab(restoring: stored, configuration: TestPages.configuration()).hasURL)
        let empty = StoredTab(id: UUID(), url: nil, lastActivity: .now)
        #expect(!BrowserTab(restoring: empty, configuration: TestPages.configuration()).hasURL)
    }
}
