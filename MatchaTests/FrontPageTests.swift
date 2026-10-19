import Foundation
@testable import Matcha
import Testing
import WebKit

/// Page targeted by the page commands (find 5.3; printing, PDF and zoom 5.4): active mini window, otherwise Peek,
/// otherwise active pane.
@MainActor
struct FrontPageTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Selected tab, at the top of today tabs, on the local page `name`.
    private func openPage(_ name: String) async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    @Test func `no window or an empty tab has nothing to search`() {
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: nil) == nil)
        _ = manager.newTab()
        #expect(manager.selectedTab != nil)
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: manager) == nil)
    }

    @Test func `the peek comes before the selected tab`() async throws {
        let source = try await openPage("source")
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: manager) === source)

        let peek = try #require(manager.openPeek(TestPages.url("apercu"), from: source))
        try await waitUntil { peek.tab.hasURL }
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: manager) === peek.tab)

        manager.closePeek()
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: manager) === source)
    }

    @Test func `the active pane of a split is the target`() async throws {
        let left = try await openPage("gauche")
        let right = try await openPage("droite")
        #expect(manager.openInSplit(left))
        #expect(manager.displayedTabs.count == 2)
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: manager) === left)
        manager.select(right)
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: manager) === right)
    }

    @Test func `a key mini window wins, even without a page`() async throws {
        _ = try await openPage("fenetre")
        let mini = BrowserTab(configuration: TestPages.configuration())
        // Empty mini window: nothing to search, and never the page of the window behind it.
        #expect(FrontPage.page(miniWindowTab: mini, tabManager: manager) == nil)

        mini.load(TestPages.url("mini"))
        try await waitUntil { mini.hasURL }
        #expect(FrontPage.page(miniWindowTab: mini, tabManager: manager) === mini)
    }

    @Test func `an unloaded tab is not a target`() async throws {
        let tab = try await openPage("dechargee")
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: manager) === tab)
        tab.unload(resettingTo: tab.url, title: tab.title)
        #expect(tab.hasURL)
        #expect(FrontPage.page(miniWindowTab: nil, tabManager: manager) == nil)
    }
}
