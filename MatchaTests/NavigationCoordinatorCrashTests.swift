import Foundation
@testable import Matcha
import Testing
import WebKit

/// Termination of a page's process (task 5.7) received by the delegate, with real web views: visible page reloaded
/// right away in the same view, hidden page reloaded when it is shown. Without a window (`TabManager.lifecycle`
/// nil), a tab displayed by the Space is visible; window tracking is checked by `PageCrashVisibilityTests`.
@MainActor
struct NavigationCoordinatorCrashTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let pages = CountingTestPages()
    private let clock = TestClock()

    init() {
        manager.coordinator.now = { [clock] in clock.now }
    }

    /// Selected tab that went through the pages “un” then “deux” (back available, text “bonjour”).
    private func openTab() async throws -> BrowserTab {
        let tab = try await openPage("un")
        tab.load(TestPages.url("deux", body: "bonjour"))
        try await waitUntil { tab.title == "deux" && tab.canGoBack && !tab.isLoading }
        return tab
    }

    /// Selected tab on the local page `name`, once loaded.
    private func openPage(_ name: String) async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: pages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    /// What WebKit calls when the process of the page of `tab` terminates.
    private func terminate(_ tab: BrowserTab) throws {
        try manager.coordinator.webViewWebContentProcessDidTerminate(#require(tab.webView))
    }

    /// Reload of `name` finished: `count` requests in total for this page, recovery done.
    private func waitForReload(of tab: BrowserTab, _ name: String, requests count: Int) async throws {
        try await waitUntil { pages.count(name) == count && !tab.crash.isRecovering && !tab.isLoading }
    }

    @Test func `the coordinator handles content process terminations`() {
        #expect(manager.coordinator.responds(to: #selector(WKNavigationDelegate.webViewWebContentProcessDidTerminate(_:))))
    }

    @Test func `a visible tab reloads at once in the same web view`() async throws {
        let tab = try await openTab()
        let webView = try #require(tab.webView)
        try terminate(tab)
        // Reload on the next turn; until then, the tab keeps its title and address.
        #expect(pages.count("deux") == 1)
        #expect(tab.keepsTitleAndAddress)
        #expect(!tab.crash.isShowingProblem)
        #expect(tab.title == "deux")
        #expect(tab.url == TestPages.url("deux", body: "bonjour"))

        try await waitForReload(of: tab, "deux", requests: 2)
        #expect(tab.webView === webView)
        #expect(!tab.keepsTitleAndAddress)
        #expect(tab.title == "deux")
        tab.goBack()
        try await waitUntil { tab.title == "un" && tab.canGoForward }
    }

    @Test func `a hidden tab reloads when it is shown, with its history`() async throws {
        let tab = try await openTab()
        manager.newTab()
        try terminate(tab)
        // Like going to sleep: view released, tab unchanged in the sidebar.
        #expect(tab.webView == nil)
        #expect(tab.suspension.isSuspended)
        #expect(tab.appearsLoaded)
        #expect(tab.title == "deux")
        #expect(!tab.crash.isRecovering)
        try await Task.sleep(for: .milliseconds(100))
        #expect(pages.count("deux") == 1)

        manager.select(tab)
        try await waitUntil { pages.count("deux") == 2 && tab.webView?.title == "deux" && tab.canGoBack && !tab.isLoading }
        tab.goBack()
        try await waitUntil { tab.title == "un" }
    }

    @Test func `every pane of the displayed split is visible`() async throws {
        let first = try await openTab()
        let second = try await openPage("voisin")
        #expect(manager.openInSplit(first))
        #expect(manager.selectedTab === first)
        #expect(manager.displayedTabs.contains { $0 === second })

        try terminate(second)
        #expect(second.webView != nil)
        try await waitForReload(of: second, "voisin", requests: 2)
    }

    @Test func `a Peek page is visible and reloads`() async throws {
        let tab = try await openTab()
        let peek = try #require(manager.openPeek(TestPages.url("cible"), from: tab))
        try await waitUntil { peek.tab.title == "cible" && !peek.tab.isLoading }

        try terminate(peek.tab)
        #expect(peek.tab.webView != nil)
        try await waitForReload(of: peek.tab, "cible", requests: 2)
        #expect(manager.peek?.id == peek.id)
        #expect(pages.count("deux") == 1)
    }

    @Test func `pending permission prompts are denied and the find result is forgotten`() async throws {
        let tab = try await openTab()
        let recorder = PermissionRecorder()
        try manager.coordinator.requestPermission(
            [.camera],
            origin: TestOrigins.meet,
            frameOrigin: TestOrigins.meet,
            in: #require(tab.webView),
            response: recorder.response(),
        )
        #expect(tab.permissionPrompts.current != nil)
        tab.find.present()
        tab.find.updateQuery("bonjour")
        try await waitUntil { tab.find.status == .found }

        try terminate(tab)
        #expect(recorder.answers == [false])
        #expect(tab.permissionPrompts.current == nil)
        // The bar and its text stay, to search again in the reloaded page.
        #expect(tab.find.status == .idle)
        #expect(tab.find.isPresented)
        #expect(tab.find.query == "bonjour")
        try await waitForReload(of: tab, "deux", requests: 2)
        tab.find.findNext()
        await tab.find.waitForPendingSearch()
        #expect(tab.find.status == .found)
    }

    @Test func `the page keeps its zoom`() async throws {
        let tab = try await openTab()
        tab.setPageZoom(1.25)
        try terminate(tab)
        try await waitForReload(of: tab, "deux", requests: 2)
        #expect(tab.pageZoom == 1.25)
        #expect(tab.webView?.pageZoom == 1.25)

        // Hidden, more than 30 s later: the recreated view gets the zoom back.
        clock.advance(60)
        manager.newTab()
        try terminate(tab)
        #expect(tab.webView == nil)
        manager.select(tab)
        try await waitUntil { pages.count("deux") == 3 && !tab.isLoading }
        #expect(tab.webView?.pageZoom == 1.25)
    }
}
