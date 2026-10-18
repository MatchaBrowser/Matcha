import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// Page qui plante en boucle (tâche 5.7) : au second arrêt en moins de 30 s, plus de rechargement automatique, un
/// message attend l'utilisateur ; le rechargement après un arrêt n'est pas une visite de l'historique. Vraies vues web,
/// arrêts annoncés au délégué comme le fait WebKit, horloge de test.
@MainActor
struct PageCrashLoopTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let pages = CountingTestPages()
    private let clock = TestClock()

    init() {
        manager.coordinator.now = { [clock] in clock.now }
    }

    /// Onglet sélectionné sur la page locale « page », une fois chargée.
    private func openTab() async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: pages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("page"))
        try await waitUntil { tab.title == "page" && !tab.isLoading }
        return tab
    }

    private func terminate(_ tab: BrowserTab) throws {
        try manager.coordinator.webViewWebContentProcessDidTerminate(#require(tab.webView))
    }

    /// Rechargement terminé : `count` requêtes en tout pour la page, reprise finie.
    private func waitForReload(of tab: BrowserTab, requests count: Int) async throws {
        try await waitUntil { pages.count("page") == count && !tab.crash.isRecovering && !tab.isLoading }
    }

    @Test func `a second crash within 30 seconds shows the message and waits for the user`() async throws {
        let tab = try await openTab()
        try terminate(tab)
        try await waitForReload(of: tab, requests: 2)

        clock.advance(10)
        try terminate(tab)
        #expect(tab.crash.isShowingProblem)
        #expect(tab.keepsTitleAndAddress)
        #expect(tab.webView != nil)
        #expect(tab.title == "page")
        #expect(tab.url == TestPages.url("page"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(pages.count("page") == 2)

        // Bouton « Recharger » du message, comme ⌘R : le message part tout de suite.
        tab.reload()
        #expect(!tab.crash.isShowingProblem)
        try await waitForReload(of: tab, requests: 3)

        // Encore dans les 30 s : de nouveau le message.
        clock.advance(5)
        try terminate(tab)
        #expect(tab.crash.isShowingProblem)
    }

    @Test func `crashes far apart reload each time`() async throws {
        let tab = try await openTab()
        try terminate(tab)
        try await waitForReload(of: tab, requests: 2)
        clock.advance(31)
        try terminate(tab)
        #expect(!tab.crash.isShowingProblem)
        try await waitForReload(of: tab, requests: 3)
    }

    @Test func `another address leaves the message`() async throws {
        let tab = try await openTab()
        try terminate(tab)
        try await waitForReload(of: tab, requests: 2)
        try terminate(tab)
        #expect(tab.crash.isShowingProblem)

        tab.load(TestPages.url("ailleurs"))
        #expect(!tab.crash.isShowingProblem)
        try await waitUntil { tab.title == "ailleurs" && !tab.crash.isRecovering && !tab.isLoading }
    }

    /// Un onglet quitté pendant la boucle garde sa vue et son message : il ne se recharge pas non plus quand on l'affiche.
    @Test func `a hidden page that crashed twice shows the message when shown`() async throws {
        let tab = try await openTab()
        try terminate(tab)
        try await waitForReload(of: tab, requests: 2)
        manager.newTab()
        try terminate(tab)
        #expect(tab.webView != nil)
        #expect(tab.crash.isShowingProblem)

        manager.select(tab)
        try await Task.sleep(for: .milliseconds(200))
        #expect(tab.crash.isShowingProblem)
        #expect(pages.count("page") == 2)
        tab.reload()
        try await waitForReload(of: tab, requests: 3)
    }

    /// Documentation livrée avec macOS : page locale (`file:`), retenue dans l'historique, sans réseau.
    nonisolated static let localDocs = "/usr/share/doc/postfix/html/index.html"

    /// Comme la sortie de veille (tâche 5.6) : ni le rechargement automatique ni celui du message ne sont des visites,
    /// même plus d'une minute après la visite (un rechargement ordinaire en serait une nouvelle).
    @Test(.enabled(if: FileManager.default.isReadableFile(atPath: localDocs)))
    func `a reload after a crash is not a new visit`() async throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let store = HistoryStore(container: container, now: { [clock] in clock.now })
        manager.history = HistoryScope(store: store, profileID: UUID(), spaceID: UUID())
        func visits() -> Int {
            (try? container.mainContext.fetchCount(FetchDescriptor<HistoryRecord>())) ?? -1
        }
        let tab = manager.newTab(url: URL(fileURLWithPath: Self.localDocs))
        try await waitUntil { tab.title == "Postfix Documentation" && !tab.isLoading && visits() == 1 }

        clock.advance(120)
        try terminate(tab)
        try await waitUntil { !tab.crash.isRecovering && !tab.isLoading }
        clock.advance(5)
        try terminate(tab)
        #expect(tab.crash.isShowingProblem)
        clock.advance(120)
        tab.reload()
        try await waitUntil { !tab.crash.isRecovering && !tab.isLoading }
        try await Task.sleep(for: .milliseconds(100))
        #expect(visits() == 1)
        #expect(tab.title == "Postfix Documentation")

        // Témoin : un rechargement ordinaire, plus d'une minute après, est une visite.
        clock.advance(120)
        tab.reload()
        try await waitUntil { visits() == 2 }
    }
}
