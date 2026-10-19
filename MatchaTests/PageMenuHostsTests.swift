import Foundation
@testable import Matcha
import Testing
import WebKit

/// “… in New Tab” from the context menu (task 5.9) from a private window, a mini window and a sign-in window. Real web
/// views; the window is requested from the delegate as WebKit does for a menu item (`.other`, no button or key, no
/// size). No window on screen.
@MainActor
@Suite(.serialized)
final class PageMenuHostsTests {
    private let session: BrowserSession
    private let model: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true), services: .withPopupWindows())
        model = WindowModel(session: session, defaults: nil)
        session.popupManager.prepareForTests()
    }

    isolated deinit {
        session.popupManager.closeAll()
    }

    /// Records the “new tab” choice in `webView`, then makes it request a window for `url`.
    private func openInNewTab(_ url: URL, from webView: WKWebView, coordinator: NavigationCoordinator) throws -> WKWebView? {
        let browserWebView = try #require(webView as? BrowserWebView)
        browserWebView.pageMenuIntent.choose(.backgroundTab, openingPoint: PeekLayout.center, at: .now)
        return coordinator.webView(
            webView,
            createWebViewWith: webView.configuration,
            for: FakeNavigationAction(url: url, modifierFlags: [], buttonNumber: 0, navigationType: .other),
            windowFeatures: FakeWindowFeatures(),
        )
    }

    @Test func `a private window opens a private background tab`() throws {
        let privateSession = BrowserSession.makePrivate(services: .withPopupWindows())
        let tabManager = privateSession.spaces[0].tabManager
        let page = tabManager.newTab()
        // The app's configuration, without the test pages' scheme: a web link (never loaded here).
        let link = try #require(URL(string: "https://example.org/cible"))

        let created = try openInNewTab(link, from: page.loadedWebView, coordinator: tabManager.coordinator)

        #expect(tabManager.tabs.count == 2)
        let added = try #require(tabManager.tabs.last)
        #expect(added.webView === created)
        #expect(tabManager.selectedTab === page)
        #expect(created?.configuration.websiteDataStore === tabManager.websiteDataStore)
        #expect(created?.configuration.websiteDataStore.isPersistent == false)
    }

    /// Like ⌘-click: a background tab in the target Space, with no new mini window.
    @Test func `a mini window opens a background tab in the target Space`() async throws {
        let miniWindows = MiniWindowManager.forTests(session: session)
        miniWindows.linkMainWindow(FakeMainWindowLink(windowModel: model))
        let tabManager = session.spaces[0].tabManager
        let existing = tabManager.newTab()
        let mini = miniWindows.openNew(loading: TestPages.url("ouvrant"), source: .link)
        try await waitUntil { mini.tab.title == "ouvrant" && !mini.tab.isLoading }
        #expect(!miniWindows.coordinator.pageMenuOffersPeek(in: mini.tab.loadedWebView))

        let created = try openInNewTab(TestPages.url("cible"), from: mini.tab.loadedWebView, coordinator: miniWindows.coordinator)

        #expect(tabManager.todayTabs.count == 2)
        #expect(tabManager.todayTabs.first?.webView === created)
        #expect(tabManager.selectedTab === existing)
        #expect(miniWindows.windows.map(\.id) == [mini.id])
    }

    /// As from its originating page: a background tab after it, in its window.
    @Test func `a sign-in window opens a background tab after its opener`() async throws {
        let tabManager = session.spaces[0].tabManager
        let other = tabManager.newTab()
        let opener = tabManager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        opener.load(TestPages.url("ouvrant"))
        try await waitUntil { opener.title == "ouvrant" && !opener.isLoading }
        try await opener.loadedWebView.openWindow(TestPages.url("connexion"), features: "width=500,height=600")
        try await waitUntil { session.popupManager.windows.count == 1 }
        let popup = session.popupManager.windows[0]
        let popupWebView = try #require(popup.tab.webView)
        #expect(!session.popupManager.coordinator.pageMenuOffersPeek(in: popupWebView))

        let created = try openInNewTab(TestPages.url("cible"), from: popupWebView, coordinator: session.popupManager.coordinator)

        #expect(tabManager.tabs.count == 3)
        #expect(tabManager.tabs[0] === opener && tabManager.tabs[2] === other)
        #expect(tabManager.tabs[1].webView === created)
        #expect(tabManager.selectedTab === opener)
        #expect(session.popupManager.windows.count == 1)
    }
}
