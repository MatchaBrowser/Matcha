import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// Fenêtres de connexion (tâche 5.8) ouvertes depuis les onglets d'un Space et leur aperçu, par le délégué de
/// navigation, avec de vraies vues web, les pages de `TestPages` et de vraies fenêtres (jamais affichées). Une classe :
/// les fenêtres restées ouvertes sont fermées à la fin de chaque test (leur vue SwiftUI retient leur contrôleur
/// jusqu'à la fermeture : leurs pages tourneraient jusqu'à la fin des tests). Un test à la fois : moins de vues web en
/// même temps, les attentes des autres suites (10 s) ne sont pas dépassées.
@MainActor
@Suite(.serialized)
final class PopupWindowTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let popups = PopupWindowManager.forTests()
    private let pages = CountingTestPages()

    init() {
        manager.popupWindows = popups
    }

    isolated deinit {
        popups.closeAll()
    }

    /// Onglet sélectionné sur une page locale, en tête, suivi d'un autre onglet vide.
    private func openPage() async throws -> (page: BrowserTab, other: BrowserTab) {
        let other = manager.newTab()
        let page = manager.insertTab(configuration: pages.configuration(), after: nil, select: true)
        page.load(TestPages.url("ouvrant"))
        try await waitUntil { page.title == "ouvrant" && !page.isLoading }
        return (page, other)
    }

    /// Fenêtre de connexion de la page locale `name`, ouverte par `webView` avec une taille, une fois chargée.
    private func openPopup(_ name: String = "connexion", from webView: WKWebView, count: Int = 1) async throws -> PopupWindowController {
        try await webView.openWindow(TestPages.url(name), features: "width=500,height=600")
        try await waitUntil { popups.windows.count == count }
        let popup = popups.windows[count - 1]
        try await waitUntil { popup.tab.title == name && !popup.tab.isLoading }
        return popup
    }

    @Test func `window open with a size opens a sign-in window instead of a tab`() async throws {
        let (page, other) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)

        #expect(manager.tabs.map(\.id) == [page.id, other.id])
        #expect(manager.selectedTab === page)
        #expect(popup.opener.page === page)
        #expect(popup.tab.openerID == page.id)
        #expect(popup.container.webView === popup.tab.webView)
        #expect(popup.tab.loadedWebView.uiDelegate === popups.coordinator)
        // Créée avec la configuration fournie par WebKit : la page d'origine reste joignable.
        #expect(try await popup.tab.loadedWebView.hasOpener())
        // La page à la taille demandée, sous la barre d'adresse ; sans fenêtre d'origine, au centre de l'écran.
        let content = popup.window.contentRect(forFrameRect: popup.window.frame)
        #expect(content.size == CGSize(width: 500, height: 600 + PopupAddressBar.height))
        #expect(abs(popup.window.frame.midX - PopupWindowManager.testScreen.midX) <= 0.5)
        #expect(abs(popup.window.frame.midY - PopupWindowManager.testScreen.midY) <= 0.5)
    }

    /// Barres masquées sans taille : un onglet aussi (seule la taille compte, comme dans Safari).
    @Test func `window open without a size still opens a tab`() async throws {
        let (page, _) = try await openPage()
        try await page.loadedWebView.openWindow(TestPages.url("onglet"), features: "toolbar=no,menubar=no")
        try await waitUntil { manager.tabs.count == 3 }
        #expect(popups.windows.isEmpty)
        #expect(manager.selectedTab === manager.tabs[1])
    }

    @Test func `window close from the page closes its sign-in window`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)

        _ = try await popup.tab.loadedWebView.evaluateJavaScript("window.close(); true")

        try await waitUntil { popups.windows.isEmpty }
        #expect(!popup.tab.isLoaded)
        #expect(page.isLoaded)
        #expect(manager.tabs.count == 2)
    }

    @Test func `command W closes the sign-in window, not a tab`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        let event = try #require(Self.keyEvent("w", modifiers: .command))

        #expect(popup.window.performKeyEquivalent(with: event))

        #expect(popups.windows.isEmpty)
        #expect(!popup.tab.isLoaded)
        #expect(manager.tabs.count == 2)
    }

    @Test func `only command W alone is the close shortcut`() throws {
        #expect(try PopupWindow.isCloseShortcut(#require(Self.keyEvent("w", modifiers: .command))))
        #expect(try PopupWindow.isCloseShortcut(#require(Self.keyEvent("w", modifiers: [.command, .capsLock]))))
        #expect(try !PopupWindow.isCloseShortcut(#require(Self.keyEvent("w", modifiers: [.command, .shift]))))
        #expect(try !PopupWindow.isCloseShortcut(#require(Self.keyEvent("w", modifiers: []))))
        #expect(try !PopupWindow.isCloseShortcut(#require(Self.keyEvent("q", modifiers: .command))))
    }

    @Test func `from Peek the sign-in window opens and Peek stays a peek`() async throws {
        let (page, other) = try await openPage()
        let peek = try #require(manager.openPeek(TestPages.url("apercu"), from: page))
        try await waitUntil { peek.tab.title == "apercu" && !peek.tab.isLoading }

        let popup = try await openPopup(from: peek.tab.loadedWebView)

        #expect(manager.peek?.tab === peek.tab)
        #expect(manager.tabs.map(\.id) == [page.id, other.id])
        #expect(popup.opener.page === peek.tab)
        #expect(try await popup.tab.loadedWebView.hasOpener())
    }

    /// ⌘-clic et fenêtre sans taille dans la fenêtre de connexion : comme depuis la page d'origine.
    @Test func `links of a sign-in window open in the opener's window`() async throws {
        let (page, other) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        let recorder = PolicyRecorder()
        let action = FakeNavigationAction(url: TestPages.url("conditions"), modifierFlags: .command)

        popups.coordinator.webView(popup.tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)

        #expect(recorder.policies == [.cancel])
        #expect(manager.tabs.count == 3)
        #expect(manager.tabs[0] === page && manager.tabs[2] === other)
        #expect(manager.selectedTab === page)
        try await waitUntil { manager.tabs[1].title == "conditions" }

        _ = try await popup.tab.loadedWebView.evaluateJavaScript("window.open('\(TestPages.url("aide").absoluteString)'); true")
        try await waitUntil { manager.tabs.count == 4 }
        #expect(manager.selectedTab?.openerID == page.id)
        #expect(popups.windows.count == 1)
    }

    /// Page d'origine fermée : une fenêtre sans taille ouverte par la fenêtre de connexion en devient une autre.
    @Test func `without its opener a sign-in window opens another one`() async throws {
        let (page, _) = try await openPage()
        let first = try await openPopup(from: page.loadedWebView)
        manager.close(page)

        _ = try await first.tab.loadedWebView.evaluateJavaScript("window.open('\(TestPages.url("suite").absoluteString)'); true")

        try await waitUntil { popups.windows.count == 2 }
        let second = popups.windows[1]
        #expect(second.opener.page === first.tab)
        try await waitUntil { second.tab.title == "suite" }
        #expect(manager.tabs.count == 1)
    }

    @Test func `a sign-in window can open another one with a size`() async throws {
        let (page, _) = try await openPage()
        let first = try await openPopup(from: page.loadedWebView)
        let second = try await openPopup("securite", from: first.tab.loadedWebView, count: 2)
        #expect(second.opener.page === first.tab)
        #expect(second.opener.host === popups)
        #expect(manager.tabs.count == 2)
    }

    @Test func `shift click stays a plain click in a sign-in window`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        let recorder = PolicyRecorder()
        let action = FakeNavigationAction(url: TestPages.url("suite"), modifierFlags: .shift)
        popups.coordinator.webView(popup.tab.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        #expect(recorder.policies == [.allow])
        #expect(manager.peek == nil)
    }

    /// Tâche 5.7 : la page d'une fenêtre de connexion est visible, elle se recharge aussitôt.
    @Test func `a crashed sign-in page reloads at once`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        popups.coordinator.webViewWebContentProcessDidTerminate(popup.tab.loadedWebView)
        try await waitUntil { pages.count("connexion") == 2 && !popup.tab.crash.isRecovering && !popup.tab.isLoading }
        #expect(popups.windows.count == 1)
    }

    /// Tâche 5.1 : une fenêtre qui ne fait que télécharger se ferme ; le téléchargement va au bout. Un fichier `blob:` :
    /// constaté, ni une réponse d'un gestionnaire de schéma de test ni une adresse `data:` ouvertes dans une nouvelle
    /// fenêtre ne deviennent un téléchargement.
    @Test func `a sign-in window that only downloads closes`() async throws {
        let folder = try TemporaryDownloadsFolder()
        let downloads = folder.makeManager()
        popups.coordinator.downloadManager = downloads
        let (page, _) = try await openPage()

        _ = try await page.loadedWebView.evaluateJavaScript("""
        const url = URL.createObjectURL(new Blob(['relevé'], {type: 'application/octet-stream'}));
        window.open(url, '_blank', 'width=400,height=400'); true
        """)

        try await waitUntil { downloads.items.count == 1 && !downloads.items[0].isActive }
        #expect(downloads.items[0].state == .finished)
        #expect(folder.contents().count == 1)
        try await waitUntil { popups.windows.isEmpty }
        #expect(manager.tabs.count == 2)
    }

    /// Une fenêtre qui affiche une page reste ouverte quand elle télécharge.
    @Test func `a sign-in window that shows a page stays open when it downloads`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        popups.downloadDidStart(in: popup.tab.loadedWebView)
        #expect(popups.windows.count == 1)
    }

    /// La fenêtre de connexion reste au-dessus de sa fenêtre d'origine ; celle-ci fermée, elle reste ouverte, seule.
    @Test func `the sign-in window follows its opener window until it closes`() async throws {
        let (page, _) = try await openPage()
        let popup = try await openPopup(from: page.loadedWebView)
        let parent = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true,
        )
        parent.isReleasedWhenClosed = false
        parent.level = .floating

        popup.attach(to: parent)
        #expect(popup.window.parent === parent)
        #expect(popup.window.level == .floating)

        parent.close()
        #expect(popup.window.parent == nil)
        #expect(popup.window.level == .normal)
        #expect(popups.windows.count == 1)
        popup.close()
        #expect(popups.windows.isEmpty)
    }

    private static func keyEvent(_ characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 13,
        )
    }
}
