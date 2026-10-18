import AppKit
import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// Mise en veille d'un onglet (tâche 5.6) avec de vraies vues web : la vue est libérée, l'onglet garde sa page, son
/// titre et son historique, et se recrée à la même page.
@MainActor
struct TabSuspensionTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Onglet passé par les pages locales « un » puis « deux » (précédent disponible), puis caché derrière un autre.
    private func hiddenTabWithHistory() async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("un"))
        try await waitUntil { tab.title == "un" && !tab.isLoading }
        tab.load(TestPages.url("deux"))
        try await waitUntil { tab.title == "deux" && tab.canGoBack && !tab.isLoading }
        manager.newTab()
        return tab
    }

    /// Petite capture JPEG de la page `url`.
    private func snapshot(of url: URL?) throws -> TabSnapshot {
        let image = try #require(NSImage(size: NSSize(width: 4, height: 3), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try TabSnapshot(data: #require(TabSnapshot.jpegData(from: image)), url: url, pageWidth: 800)
    }

    @Test func `suspending frees the web view and keeps the page as shown in the sidebar`() async throws {
        let tab = try await hiddenTabWithHistory()
        let url = tab.url
        let favicon = Favicon(image: NSImage(size: NSSize(width: 16, height: 16)), tone: .neutral)
        tab.favicon = favicon
        tab.suspend(snapshot: nil)

        #expect(tab.webView == nil)
        #expect(!tab.isLoaded)
        #expect(tab.appearsLoaded)
        #expect(tab.suspension.isSuspended)
        #expect(tab.url == url)
        #expect(tab.title == "deux")
        #expect(tab.displayTitle == "deux")
        #expect(tab.favicon === favicon)
        #expect(tab.savedInteractionState != nil)
        // Toujours rangé : la barre et la barre de commande le montrent.
        #expect(manager.tabs.contains { $0 === tab })
    }

    @Test func `a suspended tab comes back on its page with its history`() async throws {
        let tab = try await hiddenTabWithHistory()
        tab.suspend(snapshot: nil)

        manager.select(tab)
        #expect(tab.isLoaded)
        #expect(!tab.suspension.isSuspended)
        // Pendant le rechargement, la barre garde le titre et l'adresse.
        #expect(tab.title == "deux")
        #expect(tab.url == TestPages.url("deux"))
        try await waitUntil { tab.webView?.title == "deux" && tab.canGoBack && !tab.isLoading }
        #expect(tab.title == "deux")

        tab.goBack()
        try await waitUntil { tab.title == "un" && tab.canGoForward }
    }

    /// Un épinglé en veille garde la page où il était, pas son adresse d'origine (comme dans Arc).
    @Test func `a pinned tab keeps its current page, not its pinned address`() async throws {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("origine"))
        try await waitUntil { tab.title == "origine" && !tab.isLoading }
        manager.setPlace(tab, to: .pinned)
        tab.load(TestPages.url("ailleurs"))
        try await waitUntil { tab.title == "ailleurs" && tab.canGoBack && !tab.isLoading }
        manager.newTab()

        tab.suspend(snapshot: nil)
        #expect(tab.pinnedURL == TestPages.url("origine"))
        manager.select(tab)
        try await waitUntil { tab.webView?.title == "ailleurs" && tab.canGoBack && !tab.isLoading }
        #expect(tab.url == TestPages.url("ailleurs"))
        #expect(tab.pinnedURL == TestPages.url("origine"))

        // Fermer reste le retour à l'origine, sans historique.
        manager.close(tab)
        #expect(!tab.suspension.isSuspended)
        #expect(tab.url == TestPages.url("origine"))
        #expect(tab.savedInteractionState == nil)
    }

    @Test func `the snapshot covers the same page until it has loaded`() async throws {
        let tab = try await hiddenTabWithHistory()
        try tab.suspend(snapshot: snapshot(of: tab.url))
        #expect(tab.suspension.snapshot != nil)
        #expect(tab.suspension.cover == nil)

        manager.select(tab)
        #expect(tab.suspension.cover != nil)
        #expect(tab.suspension.snapshot == nil)
        try await waitUntil { tab.suspension.cover == nil }
        #expect(!tab.suspension.isRestoring)
        #expect(tab.title == "deux")
    }

    @Test func `a snapshot of another page never covers the tab`() async throws {
        let tab = try await hiddenTabWithHistory()
        try tab.suspend(snapshot: snapshot(of: TestPages.url("autre")))
        manager.select(tab)
        #expect(tab.suspension.cover == nil)
    }

    @Test func `loading another address drops the snapshot`() async throws {
        let tab = try await hiddenTabWithHistory()
        try tab.suspend(snapshot: snapshot(of: tab.url))
        manager.select(tab)
        #expect(tab.suspension.cover != nil)
        tab.load(TestPages.url("trois"))
        #expect(tab.suspension.cover == nil)
        try await waitUntil { tab.title == "trois" && !tab.isLoading }
    }

    @Test func `unloading or closing forgets the suspension`() async throws {
        let tab = try await hiddenTabWithHistory()
        try tab.suspend(snapshot: snapshot(of: tab.url))
        tab.unload(resettingTo: nil, title: nil)
        #expect(!tab.suspension.isSuspended)
        #expect(tab.suspension.snapshot == nil)
        #expect(!tab.appearsLoaded)
    }

    @Test func `duplicating a suspended tab keeps its history`() async throws {
        let tab = try await hiddenTabWithHistory()
        tab.suspend(snapshot: nil)
        let copy = manager.duplicate(tab)
        try await waitUntil { copy.title == "deux" && copy.canGoBack && !copy.isLoading }
        #expect(tab.suspension.isSuspended)
    }

    /// Documentation livrée avec macOS : page locale (`file:`), retenue dans l'historique, sans réseau.
    nonisolated static let localDocs = "/usr/share/doc/postfix/html/index.html"

    /// Le rechargement d'une page sortie de veille n'est pas une nouvelle visite (tâche 5.5) ; une page locale revient
    /// avec son historique.
    @Test(.enabled(if: FileManager.default.isReadableFile(atPath: localDocs)))
    func `a local page comes back without a new visit`() async throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        manager.history = HistoryScope(store: HistoryStore(container: container), profileID: UUID(), spaceID: UUID())
        func visits() -> Int {
            (try? container.mainContext.fetchCount(FetchDescriptor<HistoryRecord>())) ?? -1
        }
        let tab = manager.newTab(url: URL(fileURLWithPath: Self.localDocs))
        try await waitUntil { tab.title == "Postfix Documentation" && !tab.isLoading && visits() == 1 }
        tab.load(URL(fileURLWithPath: "/usr/share/doc/postfix/html/BASIC_CONFIGURATION_README.html"))
        try await waitUntil { tab.title?.contains("Basic Configuration") == true && !tab.isLoading && visits() == 2 }
        manager.newTab()

        tab.suspend(snapshot: nil)
        manager.select(tab)
        try await waitUntil { tab.webView?.title?.contains("Basic Configuration") == true && !tab.suspension.isRestoring }
        try await Task.sleep(for: .milliseconds(100))
        #expect(visits() == 2)

        tab.goBack()
        try await waitUntil { tab.title == "Postfix Documentation" && !tab.isLoading }
        // Une page où l'on revient est une visite, comme avant la veille.
        try await waitUntil { visits() == 3 }
    }
}
