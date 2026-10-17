import Foundation
@testable import Matcha
import Testing
import WebKit

/// Tests d'intégration avec de vraies vues web et les pages locales de `TestPages`.
@MainActor
struct NavigationCoordinatorTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Onglet chargé avec une page locale contenant `body`, suivi d'un autre onglet vide.
    private func openPage(body: String) async throws -> (page: BrowserTab, other: BrowserTab) {
        // Les nouveaux onglets vont en tête : on ouvre d'abord celui qui doit être second.
        let other = manager.newTab()
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        page.load(TestPages.url("ouvrant", body: body))
        try await waitUntil { page.title == "ouvrant" && !page.isLoading }
        return (page, other)
    }

    @Test func `tabs get the coordinator as delegates`() {
        let tab = manager.newTab()
        #expect(tab.loadedWebView.navigationDelegate === manager.coordinator)
        #expect(tab.loadedWebView.uiDelegate === manager.coordinator)
    }

    @Test func `target blank link opens a selected tab after its opener`() async throws {
        let popupURL = TestPages.url("popup")
        let (page, other) = try await openPage(body: "<a id='l' href='\(popupURL.absoluteString)' target='_blank'>lien</a>")

        _ = try await page.loadedWebView.evaluateJavaScript("document.getElementById('l').click(); true")
        try await waitUntil { manager.tabs.count == 3 }

        let popup = manager.tabs[1]
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(manager.selectedTab === popup)
        #expect(popup.openerID == page.id)
        try await waitUntil { popup.title == "popup" && !popup.isLoading }
    }

    @Test func `window open keeps the opener`() async throws {
        let (page, _) = try await openPage(body: "")

        _ = try await page.loadedWebView.evaluateJavaScript("window.open('\(TestPages.url("popup").absoluteString)'); true")
        try await waitUntil { manager.tabs.count == 3 }
        let popup = manager.tabs[1]
        try await waitUntil { popup.title == "popup" && !popup.isLoading }

        // Sans la configuration fournie par WebKit, la fenêtre ouverte perdrait son lien avec la page.
        let hasOpener = try await popup.loadedWebView.evaluateJavaScript("window.opener !== null")
        #expect(hasOpener as? Bool == true)
    }

    @Test func `window close from the page closes its tab`() async throws {
        let (page, other) = try await openPage(body: "")

        _ = try await page.loadedWebView.evaluateJavaScript("window.open('about:blank'); true")
        try await waitUntil { manager.tabs.count == 3 }
        let popup = manager.tabs[1]

        _ = try await popup.loadedWebView.evaluateJavaScript("window.close(); true")
        try await waitUntil { manager.tabs.count == 2 }
        #expect(manager.tabs.map(\.id) == [page.id, other.id])
    }

    @Test func `foreign scheme link is handed to another app`() async throws {
        var opened: [URL] = []
        manager.coordinator.openExternally = { opened.append($0)
            return true
        }
        let (page, _) = try await openPage(body: "<a id='l' href='mailto:moi@example.com'>courriel</a>")

        _ = try await page.loadedWebView.evaluateJavaScript("document.getElementById('l').click(); true")
        try await waitUntil { !opened.isEmpty }
        #expect(try opened == [#require(URL(string: "mailto:moi@example.com"))])
        #expect(page.url == TestPages.url("ouvrant", body: "<a id='l' href='mailto:moi@example.com'>courriel</a>"))
        #expect(manager.tabs.count == 2)
    }

    @Test func `command click opens background tabs in click order`() async throws {
        let (page, other) = try await openPage(body: "")
        let first = TestPages.url("un")
        let second = TestPages.url("deux")
        let recorder = PolicyRecorder()

        // Un clic synthétique en JavaScript ne transmet pas ⌘ : on appelle le délégué directement.
        for url in [first, second] {
            let action = FakeNavigationAction(url: url, modifierFlags: .command)
            manager.coordinator.webView(page.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        }

        #expect(recorder.policies == [.cancel, .cancel])
        #expect(manager.selectedTab === page)
        #expect(manager.tabs.count == 4)
        #expect(manager.tabs[0] === page && manager.tabs[3] === other)
        let (tab1, tab2) = (manager.tabs[1], manager.tabs[2])
        try await waitUntil { tab1.title == "un" && tab2.title == "deux" }
        #expect(tab1.openerID == page.id && tab2.openerID == page.id)
    }

    @Test func `plain click is allowed`() throws {
        let tab = manager.newTab()
        let recorder = PolicyRecorder()
        let action = try FakeNavigationAction(url: #require(URL(string: "https://example.com/")), modifierFlags: [])
        manager.coordinator.webView(tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        #expect(recorder.policies == [.allow])
        #expect(manager.tabs.count == 1)
    }
}

/// Garde les décisions passées au `decisionHandler` de WebKit.
@MainActor
private final class PolicyRecorder {
    private(set) var policies: [WKNavigationActionPolicy] = []

    func record(_ policy: WKNavigationActionPolicy) {
        policies.append(policy)
    }
}

/// Clic sur un lien du cadre principal, avec les modificateurs voulus.
@MainActor
private final class FakeNavigationAction: WKNavigationAction {
    private let fakeRequest: URLRequest
    private let fakeModifierFlags: NSEvent.ModifierFlags

    init(url: URL, modifierFlags: NSEvent.ModifierFlags) {
        fakeRequest = URLRequest(url: url)
        fakeModifierFlags = modifierFlags
        super.init()
    }

    override var request: URLRequest {
        fakeRequest
    }

    override var modifierFlags: NSEvent.ModifierFlags {
        fakeModifierFlags
    }

    override var navigationType: WKNavigationType {
        .linkActivated
    }

    override var buttonNumber: Int {
        0
    }

    override var targetFrame: WKFrameInfo? {
        nil
    }
}
