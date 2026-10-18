import Foundation
@testable import Matcha
import Testing
import WebKit

/// « … dans un nouvel onglet » du menu contextuel (tâche 5.9) depuis une fenêtre privée, une mini-fenêtre et une
/// fenêtre de connexion. Vraies vues web ; la fenêtre est demandée au délégué comme le fait WebKit pour un élément du
/// menu (`.other`, sans bouton ni touche, sans taille). Aucune fenêtre à l'écran.
@MainActor
@Suite(.serialized)
final class PageMenuHostsTests {
    private let session: BrowserSession
    private let model: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        session.popupWindows.prepareForTests()
    }

    isolated deinit {
        session.popupWindows.closeAll()
    }

    /// Retient dans `webView` le choix « nouvel onglet », puis lui fait demander une fenêtre pour `url`.
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
        let privateSession = BrowserSession.makePrivate()
        let tabManager = privateSession.spaces[0].tabManager
        let page = tabManager.newTab()
        // Configuration de l'app, sans le schéma des pages de test : un lien web (jamais chargé ici).
        let link = try #require(URL(string: "https://example.org/cible"))

        let created = try openInNewTab(link, from: page.loadedWebView, coordinator: tabManager.coordinator)

        #expect(tabManager.tabs.count == 2)
        let added = try #require(tabManager.tabs.last)
        #expect(added.webView === created)
        #expect(tabManager.selectedTab === page)
        #expect(created?.configuration.websiteDataStore === tabManager.websiteDataStore)
        #expect(created?.configuration.websiteDataStore.isPersistent == false)
    }

    /// Comme ⌘-clic : un onglet en arrière-plan du Space visé, sans nouvelle mini-fenêtre.
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

    /// Comme depuis sa page d'origine : un onglet en arrière-plan après elle, dans sa fenêtre.
    @Test func `a sign-in window opens a background tab after its opener`() async throws {
        let tabManager = session.spaces[0].tabManager
        let other = tabManager.newTab()
        let opener = tabManager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        opener.load(TestPages.url("ouvrant"))
        try await waitUntil { opener.title == "ouvrant" && !opener.isLoading }
        try await opener.loadedWebView.openWindow(TestPages.url("connexion"), features: "width=500,height=600")
        try await waitUntil { session.popupWindows.windows.count == 1 }
        let popup = session.popupWindows.windows[0]
        let popupWebView = try #require(popup.tab.webView)
        #expect(!session.popupWindows.coordinator.pageMenuOffersPeek(in: popupWebView))

        let created = try openInNewTab(TestPages.url("cible"), from: popupWebView, coordinator: session.popupWindows.coordinator)

        #expect(tabManager.tabs.count == 3)
        #expect(tabManager.tabs[0] === opener && tabManager.tabs[2] === other)
        #expect(tabManager.tabs[1].webView === created)
        #expect(tabManager.selectedTab === opener)
        #expect(session.popupWindows.windows.count == 1)
    }
}
