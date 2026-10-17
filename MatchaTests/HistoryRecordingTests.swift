import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// Visites retenues par le délégué de navigation commun (tâche 5.5), avec de vraies vues web : pages web simulées
/// (`loadSimulatedRequest`), sans réseau.
@MainActor
struct HistoryRecordingTests {
    private let container: ModelContainer
    private let clock = TestClock()
    private let store: HistoryStore
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let profileID = UUID()
    private let spaceID = UUID()

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        store = HistoryStore(container: container, now: { [clock] in clock.now })
        manager.history = HistoryScope(store: store, profileID: profileID, spaceID: spaceID)
    }

    private var records: [HistoryRecord] {
        let descriptor = FetchDescriptor<HistoryRecord>(sortBy: [SortDescriptor(\.visitDate)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    /// Onglet sélectionné, en tête des onglets du jour, sur la page simulée `address`.
    private func open(_ address: String, title: String = "", in manager: TabManager? = nil) async throws -> BrowserTab {
        let tab = (manager ?? self.manager).insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.history.sameDocumentDelay = .milliseconds(50)
        try await load(address, title: title, in: tab)
        return tab
    }

    /// Charge une page simulée et attend la fin de son chargement (le délégué a reçu `didFinish`).
    private func load(_ address: String, title: String, in tab: BrowserTab) async throws {
        let url = try #require(URL(string: address))
        tab.loadedWebView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<title>\(title)</title><p>page</p>")
        try await waitUntil { tab.url == url && !tab.isLoading }
        // `didFinish` arrive avec la fin du chargement ; un tour de plus pour le délégué.
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func `a finished page is recorded with its title, profile and space`() async throws {
        _ = try await open("https://example.com/docs#intro", title: "Exemple")
        try await waitUntil { records.count == 1 }
        let record = try #require(records.first)
        #expect(record.url?.absoluteString == "https://example.com/docs")
        #expect(record.urlKey == "example.com/docs")
        #expect(record.title == "Exemple")
        #expect(record.profileID == profileID)
        #expect(record.spaceID == spaceID)
        #expect(record.visitDate == fixedNow)
    }

    @Test func `a reload shortly after is the same visit, later it is a new one`() async throws {
        let tab = try await open("https://example.com/", title: "Exemple")
        try await waitUntil { records.count == 1 }
        clock.advance(30)
        try await load("https://example.com/", title: "Exemple rechargé", in: tab)
        try await waitUntil { records.first?.title == "Exemple rechargé" }
        #expect(records.count == 1)
        #expect(records.first?.visitDate == fixedNow.addingTimeInterval(30))

        clock.advance(61)
        try await load("https://example.com/", title: "Exemple", in: tab)
        try await waitUntil { records.count == 2 }
        // Une autre adresse est toujours une nouvelle visite.
        try await load("https://example.com/autre", title: "Autre", in: tab)
        try await waitUntil { records.count == 3 }
    }

    @Test func `pages that are not web pages or files are never recorded`() async throws {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(blankPage("vide"))
        try await waitUntil { tab.url == blankPage("vide") && !tab.isLoading }
        tab.load(TestPages.url("locale"))
        try await waitUntil { tab.title == "locale" && !tab.isLoading }
        try await Task.sleep(for: .milliseconds(100))
        #expect(records.isEmpty)
    }

    @Test func `a page without history scope records nothing`() async throws {
        // Fenêtre privée : le Space n'a pas d'historique.
        let privateManager = TabManager(websiteDataStore: .nonPersistent())
        let tab = try await open("https://example.com/", title: "Privé", in: privateManager)
        try await Task.sleep(for: .milliseconds(100))
        #expect(records.isEmpty)
        #expect(tab.title == "Privé")
    }

    @Test func `an address changed by the page is recorded once it settles`() async throws {
        let tab = try await open("https://app.example/", title: "Accueil")
        try await waitUntil { records.count == 1 }

        // Une rafale de `replaceState` ne retient que la dernière adresse.
        clock.advance(5)
        _ = try await tab.loadedWebView.evaluateJavaScript("""
        for (let i = 0; i < 5; i++) { history.replaceState({}, '', '/recherche?q=' + i); }
        document.title = 'Recherche'; true
        """)
        try await waitUntil { records.count == 2 }
        try await Task.sleep(for: .milliseconds(150))
        #expect(records.map(\.urlKey) == ["app.example", "app.example/recherche?q=4"])
        #expect(records.last?.title == "Recherche")

        // Un fragment seul n'est pas une nouvelle page.
        clock.advance(120)
        _ = try await tab.loadedWebView.evaluateJavaScript("location.hash = 'section'; true")
        try await waitUntil { tab.url?.fragment == "section" }
        try await Task.sleep(for: .milliseconds(150))
        #expect(records.count == 2)

        _ = try await tab.loadedWebView.evaluateJavaScript("history.pushState({}, '', '/article'); true")
        try await waitUntil { records.count == 3 }
        #expect(records.last?.urlKey == "app.example/article")
    }

    @Test func `a title set after loading renames the visit only shortly after`() async throws {
        let tab = try await open("https://example.com/", title: "")
        try await waitUntil { records.count == 1 }
        #expect(records.first?.title == nil)

        clock.advance(2)
        _ = try await tab.loadedWebView.evaluateJavaScript("document.title = 'Tardif'; true")
        try await waitUntil { records.first?.title == "Tardif" }

        clock.advance(10)
        _ = try await tab.loadedWebView.evaluateJavaScript("document.title = '(1) Nouveau message'; true")
        try await waitUntil { tab.title == "(1) Nouveau message" }
        try await Task.sleep(for: .milliseconds(50))
        #expect(records.first?.title == "Tardif")
    }

    @Test func `mini window pages are recorded in their profile without space`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let miniWindows = MiniWindowManager.forTests(session: session)
        let mini = miniWindows.openNew(source: .menu)
        let url = try #require(URL(string: "https://mini.example/"))
        mini.tab.loadedWebView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<title>Mini</title>")
        let context = session.container.mainContext
        try await waitUntil { ((try? context.fetchCount(FetchDescriptor<HistoryRecord>())) ?? 0) == 1 }
        let record = try #require(try context.fetch(FetchDescriptor<HistoryRecord>()).first)
        #expect(record.profileID == mini.profileID)
        #expect(record.profileID != nil)
        #expect(record.spaceID == nil)
        #expect(record.title == "Mini")
        mini.close()
    }
}
