import Foundation
@testable import Matcha
import Testing
import WebKit

/// Arrêt du processus d'une page (tâche 5.7) reçu par le délégué, avec de vraies vues web : page visible rechargée
/// tout de suite dans la même vue, page cachée rechargée quand on l'affiche. Sans fenêtre (`TabManager.lifecycle` nil),
/// un onglet affiché par le Space est visible ; le suivi des fenêtres est vérifié par `PageCrashVisibilityTests`.
@MainActor
struct NavigationCoordinatorCrashTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let pages = CountingTestPages()
    private let clock = TestClock()

    init() {
        manager.coordinator.now = { [clock] in clock.now }
    }

    /// Onglet sélectionné passé par les pages « un » puis « deux » (précédent disponible, texte « bonjour »).
    private func openTab() async throws -> BrowserTab {
        let tab = try await openPage("un")
        tab.load(TestPages.url("deux", body: "bonjour"))
        try await waitUntil { tab.title == "deux" && tab.canGoBack && !tab.isLoading }
        return tab
    }

    /// Onglet sélectionné sur la page locale `name`, une fois chargée.
    private func openPage(_ name: String) async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: pages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    /// Ce que WebKit appelle quand le processus de la page de `tab` s'arrête.
    private func terminate(_ tab: BrowserTab) throws {
        try manager.coordinator.webViewWebContentProcessDidTerminate(#require(tab.webView))
    }

    /// Rechargement de `name` terminé : `count` requêtes en tout pour cette page, reprise finie.
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
        // Rechargement au tour suivant ; d'ici là, l'onglet garde son titre et son adresse.
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
        // Comme une mise en veille : vue libérée, onglet inchangé dans la barre.
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
        // La barre et son texte restent pour chercher de nouveau dans la page rechargée.
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

        // Caché, plus de 30 s après : la vue recréée reprend le zoom.
        clock.advance(60)
        manager.newTab()
        try terminate(tab)
        #expect(tab.webView == nil)
        manager.select(tab)
        try await waitUntil { pages.count("deux") == 3 && !tab.isLoading }
        #expect(tab.webView?.pageZoom == 1.25)
    }
}
