import Foundation
@testable import Matcha
import Testing
import WebKit

/// Aperçu (Peek, tâche 4.4) par le délégué de navigation, avec de vraies vues web et les pages de `TestPages`.
/// Un clic simulé en JavaScript n'emporte aucune touche : les clics avec Maj passent par `FakeNavigationAction`.
@MainActor
struct NavigationCoordinatorPeekTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Onglet sélectionné sur une page locale, en tête, suivi d'un autre onglet vide.
    private func openPage() async throws -> (page: BrowserTab, other: BrowserTab) {
        let other = manager.newTab()
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        page.load(TestPages.url("ouvrant"))
        try await waitUntil { page.title == "ouvrant" && !page.isLoading }
        return (page, other)
    }

    /// Envoie au délégué un clic sur `url` dans `webView` et rend les décisions prises.
    private func click(
        _ url: URL,
        in webView: WKWebView,
        modifiers: NSEvent.ModifierFlags = .shift,
        button: Int = 1,
    ) -> [WKNavigationActionPolicy] {
        let recorder = PolicyRecorder()
        let action = FakeNavigationAction(url: url, modifierFlags: modifiers, buttonNumber: button)
        manager.coordinator.webView(webView, decidePolicyFor: action, decisionHandler: recorder.record)
        return recorder.policies
    }

    /// Aperçu de la page locale `name`, ouvert par Maj+clic depuis `page`, une fois chargé.
    private func shiftClick(_ name: String, from page: BrowserTab) async throws -> Peek {
        #expect(click(TestPages.url(name), in: page.loadedWebView) == [.cancel])
        let peek = try #require(manager.peek)
        try await waitUntil { peek.tab.title == name && !peek.tab.isLoading }
        return peek
    }

    @Test func `shift click opens Peek without a new tab`() async throws {
        let (page, _) = try await openPage()
        let peek = try await shiftClick("cible", from: page)
        #expect(peek.sourceTabID == page.id)
        #expect(page.url == TestPages.url("ouvrant"))
        #expect(manager.tabs.count == 2)
        #expect(manager.selectedTab === page)
    }

    @Test func `shift click inside Peek stays in Peek`() async throws {
        let (page, _) = try await openPage()
        let peek = try await shiftClick("cible", from: page)
        let webView = try #require(peek.tab.webView)

        // Le faux n'a pas de cadre cible : c'est un lien qui ouvrirait une fenêtre, chargé dans l'aperçu.
        #expect(click(TestPages.url("deux"), in: webView) == [.cancel])
        try await waitUntil { peek.tab.title == "deux" && !peek.tab.isLoading }
        #expect(manager.peek?.id == peek.id)
        #expect(manager.tabs.count == 2)
    }

    @Test func `command click inside Peek opens a background tab after the source`() async throws {
        let (page, other) = try await openPage()
        let peek = try await shiftClick("cible", from: page)
        let webView = try #require(peek.tab.webView)

        #expect(click(TestPages.url("fond"), in: webView, modifiers: .command) == [.cancel])

        #expect(manager.tabs.count == 3)
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(manager.tabs[1].openerID == page.id)
        #expect(manager.selectedTab === page)
        #expect(manager.peek?.id == peek.id)
    }

    @Test func `window open from Peek turns it into a tab first`() async throws {
        let (page, other) = try await openPage()
        let peek = try await shiftClick("cible", from: page)
        let webView = try #require(peek.tab.webView)

        _ = try await webView.evaluateJavaScript("window.open('\(TestPages.url("popup").absoluteString)'); true")
        try await waitUntil { manager.tabs.count == 4 }

        let popup = manager.tabs[2]
        #expect(manager.tabs.map(\.id) == [page.id, peek.tab.id, popup.id, other.id])
        #expect(manager.selectedTab === popup)
        #expect(manager.peek == nil)
        try await waitUntil { popup.title == "popup" && !popup.isLoading }
        let hasOpener = try await popup.loadedWebView.evaluateJavaScript("window.opener !== null")
        #expect(hasOpener as? Bool == true)
    }

    @Test func `window close from Peek closes it`() async throws {
        let (page, _) = try await openPage()
        let peek = try await shiftClick("cible", from: page)

        // Accepté par WebKit tant que l'historique de la vue n'a qu'une page.
        _ = try await peek.tab.loadedWebView.evaluateJavaScript("window.close(); true")
        try await waitUntil { manager.peek == nil }
        #expect(peek.tab.webView == nil)
        #expect(manager.tabs.count == 2)
    }

    @Test func `pinned link to another site opens Peek when the option is on`() async throws {
        let pinned = manager.newTab()
        manager.setPlace(pinned, to: .pinned)
        let html = "<p>Boîte de réception</p>"
        let inbox = try #require(URL(string: "https://mail.app.test/inbox"))
        pinned.loadedWebView.loadSimulatedRequest(URLRequest(url: inbox), responseHTML: html)
        try await waitUntil { pinned.url?.host() == "mail.app.test" && !pinned.isLoading }
        var optionOn = true
        manager.coordinator.opensPinnedLinksInPeek = { optionOn }
        let otherSite = try #require(URL(string: "https://news.peek.test/a"))
        let sameSite = try #require(URL(string: "https://accounts.app.test/"))

        #expect(click(otherSite, in: pinned.loadedWebView, modifiers: []) == [.cancel])
        #expect(manager.peek?.sourceTabID == pinned.id)
        manager.closePeek()

        #expect(click(sameSite, in: pinned.loadedWebView, modifiers: []) == [.allow])
        optionOn = false
        #expect(click(otherSite, in: pinned.loadedWebView, modifiers: []) == [.allow])
        optionOn = true
        let today = manager.newTab()
        today.loadedWebView.loadSimulatedRequest(URLRequest(url: inbox), responseHTML: html)
        try await waitUntil { today.url?.host() == "mail.app.test" && !today.isLoading }
        #expect(click(otherSite, in: today.loadedWebView, modifiers: []) == [.allow])
        #expect(manager.peek == nil)
    }

    @Test func `a tab that is not selected follows the link`() async throws {
        let (page, other) = try await openPage()
        // Configuration de l'app, sans le schéma des pages de test : un lien web.
        let link = try #require(URL(string: "https://example.org/cible"))
        #expect(click(link, in: other.loadedWebView) == [.allow])
        #expect(manager.peek == nil)
        #expect(manager.selectedTab === page)
    }
}
