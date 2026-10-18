import Foundation
@testable import Matcha
import Testing
import WebKit

/// Fenêtre ouverte pour un choix du menu contextuel (tâche 5.9), par le délégué de navigation des onglets d'un
/// Space, avec de vraies vues web et les pages de `TestPages`. La fenêtre est demandée au délégué comme le fait
/// WebKit pour « … dans une nouvelle fenêtre » (vérifié : `.other`, sans bouton ni touche, sans taille).
@MainActor
struct NavigationCoordinatorPageMenuTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Onglet sélectionné sur une page locale, en tête, suivi d'un autre onglet vide.
    private func openPage() async throws -> (page: BrowserTab, other: BrowserTab) {
        let other = manager.newTab()
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        page.load(TestPages.url("ouvrant"))
        try await waitUntil { page.title == "ouvrant" && !page.isLoading }
        return (page, other)
    }

    /// Retient dans la vue web de `tab` le choix `destination`, comme un élément du menu.
    private func choose(_ destination: PageMenuDestination, in tab: BrowserTab) throws {
        let webView = try #require(tab.loadedWebView as? BrowserWebView)
        webView.pageMenuIntent.choose(destination, openingPoint: PeekLayout.center, at: .now)
    }

    private func pendingIntent(of tab: BrowserTab) -> PageMenuIntent? {
        (tab.webView as? BrowserWebView)?.pageMenuIntent.intent
    }

    /// Fenêtre que la page de `tab` demande pour `url`.
    private func requestWindow(
        _ url: URL,
        from tab: BrowserTab,
        type: WKNavigationType = .other,
        features: FakeWindowFeatures = FakeWindowFeatures(),
    ) -> WKWebView? {
        manager.coordinator.webView(
            tab.loadedWebView,
            createWebViewWith: tab.loadedWebView.configuration,
            for: FakeNavigationAction(url: url, modifierFlags: [], buttonNumber: 0, navigationType: type),
            windowFeatures: features,
        )
    }

    @Test func `open in new tab adds a background tab after the page, once`() async throws {
        let (page, other) = try await openPage()
        try choose(.backgroundTab, in: page)

        let created = requestWindow(TestPages.url("cible"), from: page)

        #expect(manager.tabs.count == 3)
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(created != nil && manager.tabs[1].webView === created)
        #expect(manager.tabs[1].openerID == page.id)
        #expect(manager.selectedTab === page)
        #expect(pendingIntent(of: page) == nil)

        // La fenêtre suivante vient de la page (`window.open`) : un onglet au premier plan, comme avant.
        let next = requestWindow(TestPages.url("popup"), from: page)
        #expect(manager.tabs.count == 4)
        #expect(manager.selectedTab?.webView === next)
    }

    @Test func `the choice expires after one second`() async throws {
        let (page, _) = try await openPage()
        try choose(.backgroundTab, in: page)
        manager.coordinator.now = { .now.addingTimeInterval(2) }

        let created = requestWindow(TestPages.url("popup"), from: page)

        #expect(manager.selectedTab?.webView === created)
        #expect(pendingIntent(of: page) == nil)
    }

    /// Un choix fait dans une autre page ne vaut pas pour celle-ci (vrai `window.open`) ; un lien `target=_blank` ne
    /// le prend jamais.
    @Test func `page windows are never taken for a menu choice`() async throws {
        let (page, other) = try await openPage()
        try choose(.backgroundTab, in: other)

        _ = try await page.loadedWebView.evaluateJavaScript("window.open('\(TestPages.url("popup").absoluteString)'); true")
        try await waitUntil { manager.tabs.count == 3 }
        #expect(manager.selectedTab === manager.tabs[1])
        #expect(manager.tabs[1].openerID == page.id)
        #expect(pendingIntent(of: other) != nil)

        try choose(.backgroundTab, in: page)
        let blank = requestWindow(TestPages.url("blank"), from: page, type: .linkActivated)
        #expect(manager.selectedTab?.webView === blank)
        #expect(pendingIntent(of: page) != nil)
    }

    @Test func `open in new tab from Peek keeps the Peek`() async throws {
        let (page, other) = try await openPage()
        let recorder = PolicyRecorder()
        let shiftClick = FakeNavigationAction(url: TestPages.url("cible"), modifierFlags: .shift)
        manager.coordinator.webView(page.loadedWebView, decidePolicyFor: shiftClick, decisionHandler: recorder.record)
        let peek = try #require(manager.peek)
        try await waitUntil { peek.tab.title == "cible" && !peek.tab.isLoading }
        try choose(.backgroundTab, in: peek.tab)

        let created = requestWindow(TestPages.url("fond"), from: peek.tab)

        #expect(manager.tabs.count == 3)
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(manager.tabs[1].webView === created && manager.tabs[1].openerID == page.id)
        #expect(manager.peek?.id == peek.id)
        #expect(manager.selectedTab === page)
    }

    @Test func `open in Peek opens the link in Peek`() async throws {
        let (page, _) = try await openPage()
        try choose(.peek, in: page)

        #expect(requestWindow(TestPages.url("cible"), from: page) == nil)

        let peek = try #require(manager.peek)
        #expect(peek.sourceTabID == page.id)
        #expect(peek.openingPoint == PeekLayout.center)
        try await waitUntil { peek.tab.title == "cible" && !peek.tab.isLoading }
        #expect(manager.tabs.count == 2)
        #expect(manager.selectedTab === page)
    }

    /// Aperçu refusé (onglet qui n'est pas affiché, adresse `data:`) : un onglet en arrière-plan plutôt que rien.
    @Test func `open in Peek falls back to a background tab`() async throws {
        let (page, other) = try await openPage()
        try choose(.peek, in: other)
        // Configuration de l'app, sans le schéma des pages de test : un lien web (jamais chargé ici).
        let link = try #require(URL(string: "https://example.org/cible"))
        let hidden = requestWindow(link, from: other)
        #expect(hidden != nil && manager.tabs.last?.webView === hidden)

        try choose(.peek, in: page)
        let data = try #require(URL(string: "data:text/html,<p>donn%C3%A9es</p>"))
        let created = requestWindow(data, from: page)
        #expect(created != nil && manager.tabs[1].webView === created)

        #expect(manager.peek == nil)
        #expect(manager.tabs.count == 4)
        #expect(manager.selectedTab === page)
    }

    @Test func `a link to another app opens that app`() async throws {
        let (page, _) = try await openPage()
        var opened: [URL] = []
        manager.coordinator.openExternally = { url in
            opened.append(url)
            return true
        }
        try choose(.backgroundTab, in: page)
        let mail = try #require(URL(string: "mailto:contact@example.org"))

        #expect(requestWindow(mail, from: page) == nil)
        #expect(opened == [mail])
        #expect(manager.tabs.count == 2)
    }

    /// Une fenêtre de connexion (taille donnée) n'est jamais celle du menu : le choix attend encore la sienne.
    @Test func `a sign-in window is never taken for the choice`() async throws {
        let (page, _) = try await openPage()
        let popups = PopupWindowManager.forTests()
        defer { popups.closeAll() }
        manager.popupWindows = popups
        try choose(.backgroundTab, in: page)

        _ = requestWindow(TestPages.url("connexion"), from: page, features: FakeWindowFeatures(width: 500, height: 600))

        #expect(popups.windows.count == 1)
        #expect(manager.tabs.count == 2)
        #expect(pendingIntent(of: page) != nil)
        let created = requestWindow(TestPages.url("cible"), from: page)
        #expect(manager.tabs[1].webView === created && manager.selectedTab === page)
    }

    @Test func `the menu offers Peek in tabs only`() async throws {
        let (page, other) = try await openPage()
        #expect(manager.coordinator.pageMenuOffersPeek(in: page.loadedWebView))
        #expect(manager.coordinator.pageMenuOffersPeek(in: other.loadedWebView))

        let peek = try #require(manager.openPeek(TestPages.url("cible"), from: page))
        #expect(!manager.coordinator.pageMenuOffersPeek(in: peek.tab.loadedWebView))
        #expect(!manager.coordinator.pageMenuOffersPeek(in: WKWebView()))
    }
}
