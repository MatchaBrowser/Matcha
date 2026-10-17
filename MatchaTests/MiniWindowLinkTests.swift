import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// Liens dans une mini-fenêtre, par le délégué de navigation commun (`NavigationCoordinator`, hôte
/// `MiniWindowManager`), avec de vraies vues web et les pages de `TestPages`.
@MainActor
struct MiniWindowLinkTests {
    private let session: BrowserSession
    private let model: WindowModel
    private let manager: MiniWindowManager

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        manager = .forTests(session: session)
    }

    /// Mini-fenêtre ouverte sur la page locale `name` contenant `body`, une fois chargée.
    private func openPage(_ name: String, body: String = "") async throws -> MiniWindowController {
        let mini = manager.openNew(loading: TestPages.url(name, body: body), source: .link)
        try await waitUntil { mini.tab.title == name && !mini.tab.isLoading }
        return mini
    }

    /// Envoie au délégué un clic sur `url` dans la page de `mini` et rend les décisions prises.
    private func click(
        _ url: URL,
        in mini: MiniWindowController,
        modifiers: NSEvent.ModifierFlags,
        button: Int = 1,
    ) -> [WKNavigationActionPolicy] {
        let recorder = PolicyRecorder()
        let action = FakeNavigationAction(url: url, modifierFlags: modifiers, buttonNumber: button)
        manager.coordinator.webView(mini.tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        return recorder.policies
    }

    @Test func `pages of mini windows get the shared coordinator`() async throws {
        let mini = try await openPage("page")
        #expect(mini.tab.loadedWebView.navigationDelegate === manager.coordinator)
        #expect(mini.tab.loadedWebView.uiDelegate === manager.coordinator)
    }

    @Test func `target blank opens another mini window in the same profile`() async throws {
        let popupURL = TestPages.url("popup")
        let mini = try await openPage("ouvrant", body: "<a id='l' href='\(popupURL.absoluteString)' target='_blank'>lien</a>")

        _ = try await mini.tab.loadedWebView.evaluateJavaScript("document.getElementById('l').click(); true")
        try await waitUntil { manager.windows.count == 2 }

        let popup = manager.windows[1]
        #expect(popup.profileID == mini.profileID)
        #expect(popup.tab.openerID == mini.tab.id)
        #expect(!popup.commandBar.isPresented)
        try await waitUntil { popup.tab.title == "popup" }
        #expect(popup.container.webView === popup.tab.webView)
        #expect(mini.tab.title == "ouvrant")
        #expect(session.hasNoTabs)
    }

    @Test func `command click adds a background tab to the target Space`() async throws {
        manager.linkMainWindow(FakeMainWindowLink(windowModel: model))
        let tabManager = session.spaces[0].tabManager
        let existing = tabManager.newTab()
        let mini = try await openPage("ouvrant")
        let url = blankPage("lien")

        #expect(click(url, in: mini, modifiers: .command) == [.cancel])

        #expect(tabManager.todayTabs.count == 2)
        #expect(tabManager.selectedTab === existing)
        let added = try #require(tabManager.todayTabs.first)
        try await waitUntil { added.url == url }
        #expect(manager.windows.map(\.id) == [mini.id])
        #expect(mini.tab.title == "ouvrant")
    }

    @Test func `middle click and shift command click also stay in the background`() async throws {
        let tabManager = session.spaces[0].tabManager
        let existing = tabManager.newTab()
        let mini = try await openPage("ouvrant")

        #expect(click(blankPage("milieu"), in: mini, modifiers: [], button: 4) == [.cancel])
        // ⇧⌘-clic ouvrirait l'onglet au premier plan dans la fenêtre : depuis une mini-fenêtre, il reste derrière.
        #expect(click(blankPage("devant"), in: mini, modifiers: [.command, .shift]) == [.cancel])

        #expect(tabManager.todayTabs.count == 3)
        #expect(tabManager.selectedTab === existing)
        #expect(manager.windows.count == 1)
    }

    @Test func `shift click stays a plain click in a mini window`() async throws {
        let mini = try await openPage("ouvrant")
        #expect(click(TestPages.url("suite"), in: mini, modifiers: .shift) == [.allow])
        #expect(session.spaces[0].tabManager.peek == nil)
    }

    @Test func `window close from a popup closes only its mini window`() async throws {
        let mini = try await openPage("ouvrant")
        _ = try await mini.tab.loadedWebView.evaluateJavaScript("window.open('about:blank'); true")
        try await waitUntil { manager.windows.count == 2 }
        let popup = manager.windows[1]

        _ = try await popup.tab.loadedWebView.evaluateJavaScript("window.close(); true")

        try await waitUntil { manager.windows.count == 1 }
        #expect(manager.windows[0] === mini)
        #expect(!popup.tab.isLoaded)
        #expect(mini.tab.isLoaded)
    }
}
