import Foundation
@testable import Matcha
import Testing
import WebKit

/// Peek (task 4.4) in the tab manager: outside the sidebar, closing, “Open as Tab”.
@MainActor
@Suite(.webKit)
struct TabManagerPeekTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Selected tab, at the top of today tabs, on the local page `name`.
    private func openSource(_ name: String = "source") async throws -> BrowserTab {
        let source = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        source.load(TestPages.url(name))
        try await waitUntil { source.title == name && !source.isLoading }
        return source
    }

    /// Peek of the local page `name` opened from `source`, once loaded.
    private func openPeek(from source: BrowserTab, _ name: String = "apercu") async throws -> Peek {
        let peek = try #require(manager.openPeek(TestPages.url(name), from: source))
        try await waitUntil { peek.tab.title == name && !peek.tab.isLoading }
        return peek
    }

    @Test func `opening Peek keeps it out of the sidebar`() async throws {
        let source = try await openSource()
        let layout = manager.layout
        let peek = try await openPeek(from: source)

        #expect(manager.tabs.map(\.id) == [source.id])
        #expect(manager.layout == layout)
        #expect(manager.selectedTab === source)
        let webView = try #require(peek.tab.webView)
        #expect(manager.tab(for: webView) == nil)
        #expect(manager.tabOrPeek(for: webView) === peek.tab)
        #expect(manager.isPeek(webView))
        #expect(peek.tab.openerID == source.id)
        #expect(peek.sourceTabID == source.id)
        // Same profile: same data store, same schemes.
        #expect(webView.configuration.websiteDataStore === source.loadedWebView.configuration.websiteDataStore)
        #expect(webView.configuration.urlSchemeHandler(forURLScheme: TestPages.scheme) != nil)
    }

    @Test func `opening Peek needs a displayed source`() async throws {
        let source = try await openSource()
        let background = manager.newTab(select: false)
        #expect(!manager.canPeek(from: background))
        #expect(manager.openPeek(TestPages.url("apercu"), from: background) == nil)
        #expect(manager.peek == nil)
        #expect(manager.selectedTab === source)
    }

    @Test func `opening Peek from Peek loads in place`() async throws {
        let source = try await openSource()
        let peek = try await openPeek(from: source)
        #expect(manager.canPeek(from: peek.tab))
        #expect(manager.openPeek(TestPages.url("deux"), from: peek.tab)?.id == peek.id)
        try await waitUntil { peek.tab.title == "deux" && !peek.tab.isLoading }
        #expect(manager.peek?.id == peek.id)
        #expect(peek.tab.canGoBack)
    }

    @Test func `a second Peek replaces the first`() async throws {
        let source = try await openSource()
        let first = try await openPeek(from: source, "un")
        let second = try await openPeek(from: source, "deux")
        #expect(first.tab.webView == nil)
        #expect(manager.peek?.id == second.id)
    }

    @Test func `closing Peek frees its page and keeps the tabs`() async throws {
        let source = try await openSource()
        let peek = try await openPeek(from: source)
        manager.closePeek()
        #expect(manager.peek == nil)
        #expect(peek.tab.webView == nil)
        #expect(manager.tabs.map(\.id) == [source.id])
        #expect(manager.selectedTab === source)
        #expect(source.isLoaded)
    }

    @Test func `selecting another tab closes Peek`() async throws {
        let source = try await openSource()
        let other = manager.newTab(select: false)
        let peek = try await openPeek(from: source)
        manager.select(other)
        #expect(manager.peek == nil)
        #expect(peek.tab.webView == nil)
    }

    @Test func `selecting the source keeps Peek`() async throws {
        let source = try await openSource()
        let peek = try await openPeek(from: source)
        manager.select(source)
        #expect(manager.peek?.id == peek.id)
        #expect(peek.tab.isLoaded)
    }

    @Test func `closing the source closes Peek`() async throws {
        let source = try await openSource()
        manager.newTab(select: false)
        let peek = try await openPeek(from: source)
        manager.close(source)
        #expect(manager.peek == nil)
        #expect(peek.tab.webView == nil)
    }

    @Test func `opening as a tab keeps the page after its source`() async throws {
        let other = manager.newTab()
        let source = try await openSource()
        // A tab already opened from the source (⌘-click): Peek goes after it.
        let child = manager.insertTab(configuration: source.configuration, after: source, select: false)
        let peek = try await openPeek(from: source)
        let webView = try #require(peek.tab.webView)
        _ = try await webView.evaluateJavaScript("window.marker = 42; true")

        let opened = manager.openPeekAsTab()

        #expect(opened === peek.tab)
        #expect(opened?.webView === webView)
        #expect(manager.tab(for: webView) === peek.tab)
        #expect(manager.tabs.map(\.id) == [source.id, child.id, peek.tab.id, other.id])
        #expect(manager.selectedTab === peek.tab)
        #expect(manager.peek == nil)
        // Same page, no reload: the JavaScript state is intact.
        let marker = try await webView.evaluateJavaScript("window.marker")
        #expect((marker as? NSNumber)?.intValue == 42)
        #expect(peek.tab.title == "apercu")
    }

    @Test func `opening as a tab from a pinned tab goes to the top of Today`() async throws {
        let today = manager.newTab()
        let source = try await openSource()
        manager.setPlace(source, to: .pinned)
        #expect(manager.selectedTab === source)
        let peek = try await openPeek(from: source)

        manager.openPeekAsTab()

        #expect(manager.todayTabs.map(\.id) == [peek.tab.id, today.id])
        #expect(manager.place(of: peek.tab) == .today)
        #expect(manager.selectedTab === peek.tab)
    }

    @Test func `the peek is never saved`() async throws {
        let source = try await openSource()
        let peek = try await openPeek(from: source)
        #expect(manager.storedTabs().map(\.id) == [source.id])
        #expect(!manager.storedTabs().contains { $0.id == peek.tab.id })
    }

    @Test func `front tab is Peek while it is open`() async throws {
        let source = try await openSource()
        #expect(manager.frontTab === source)
        let peek = try await openPeek(from: source)
        #expect(manager.frontTab === peek.tab)
        manager.closePeek()
        #expect(manager.frontTab === source)
    }

    @Test func `insertion anchor of Peek is its source`() async throws {
        let source = try await openSource()
        let peek = try await openPeek(from: source)
        let stray = WKWebView(frame: .zero, configuration: TestPages.configuration())
        #expect(try manager.insertionAnchor(for: #require(peek.tab.webView)) === source)
        #expect(manager.insertionAnchor(for: source.loadedWebView) === source)
        #expect(manager.insertionAnchor(for: stray) == nil)
        #expect(manager.tabOrPeek(for: stray) == nil)
    }

    // MARK: Split view

    @Test func `any pane of a split can open Peek and becomes active`() async throws {
        let first = try await openSource("un")
        let second = try await openSource("deux")
        #expect(manager.openInSplit(first))
        #expect(manager.selectedTab === first)
        #expect(manager.canPeek(from: second))

        let peek = try await openPeek(from: second)

        #expect(manager.selectedTab === second)
        #expect(peek.sourceTabID == second.id)
        #expect(manager.displayedTabs.map(\.id) == [second.id, first.id])
    }

    @Test func `opening as a tab from a split goes after the split, alone`() async throws {
        let other = manager.newTab()
        let first = try await openSource("un")
        let second = try await openSource("deux")
        manager.openInSplit(first)
        let peek = try await openPeek(from: first)

        manager.openPeekAsTab()

        #expect(manager.todayTabs.map(\.id) == [second.id, first.id, peek.tab.id, other.id])
        #expect(manager.split(containing: peek.tab) == nil)
        #expect(manager.displayedTabs.map(\.id) == [peek.tab.id])
        expectSplitInvariants(manager.layout)
    }
}
