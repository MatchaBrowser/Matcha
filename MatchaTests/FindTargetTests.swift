import Foundation
@testable import Matcha
import Testing
import WebKit

/// Page visée par ⌘F, ⌘G et ⇧⌘G (tâche 5.3) : mini-fenêtre active, sinon aperçu, sinon panneau actif.
@MainActor
struct FindTargetTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Onglet sélectionné, en tête des onglets du jour, sur la page locale `name`.
    private func openPage(_ name: String) async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    @Test func `no window or an empty tab has nothing to search`() {
        #expect(FindTarget.page(miniWindowTab: nil, tabManager: nil) == nil)
        _ = manager.newTab()
        #expect(manager.selectedTab != nil)
        #expect(FindTarget.page(miniWindowTab: nil, tabManager: manager) == nil)
    }

    @Test func `the peek comes before the selected tab`() async throws {
        let source = try await openPage("source")
        #expect(FindTarget.page(miniWindowTab: nil, tabManager: manager) === source)

        let peek = try #require(manager.openPeek(TestPages.url("apercu"), from: source))
        try await waitUntil { peek.tab.hasURL }
        #expect(FindTarget.page(miniWindowTab: nil, tabManager: manager) === peek.tab)

        manager.closePeek()
        #expect(FindTarget.page(miniWindowTab: nil, tabManager: manager) === source)
    }

    @Test func `the active pane of a split is the target`() async throws {
        let left = try await openPage("gauche")
        let right = try await openPage("droite")
        #expect(manager.openInSplit(left))
        #expect(manager.displayedTabs.count == 2)
        #expect(FindTarget.page(miniWindowTab: nil, tabManager: manager) === left)
        manager.select(right)
        #expect(FindTarget.page(miniWindowTab: nil, tabManager: manager) === right)
    }

    @Test func `a key mini window wins, even without a page`() async throws {
        _ = try await openPage("fenetre")
        let mini = BrowserTab(configuration: TestPages.configuration())
        // Mini-fenêtre vide : rien à chercher, et jamais la page de la fenêtre derrière elle.
        #expect(FindTarget.page(miniWindowTab: mini, tabManager: manager) == nil)

        mini.load(TestPages.url("mini"))
        try await waitUntil { mini.hasURL }
        #expect(FindTarget.page(miniWindowTab: mini, tabManager: manager) === mini)
    }
}
