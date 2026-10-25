import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// Visits recorded by the common navigation delegate (task 5.5), with real web views: simulated web pages
/// (`loadSimulatedRequest`), without network.
@MainActor
@Suite(.webKit)
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

    /// Selected tab, at the top of today tabs, on the simulated page `address`.
    private func open(_ address: String, title: String = "", in manager: TabManager? = nil) async throws -> BrowserTab {
        let tab = (manager ?? self.manager).insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.history.sameDocumentDelay = .milliseconds(50)
        try await load(address, title: title, in: tab)
        return tab
    }

    /// Loads a simulated page and waits until it has finished loading (the delegate has received `didFinish`).
    private func load(_ address: String, title: String, in tab: BrowserTab) async throws {
        let url = try #require(URL(string: address))
        let finished = tab.history.finishedLoads
        tab.loadedWebView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<title>\(title)</title><p>page</p>")
        // `didFinish` handled, the page recorded or not (review TS2).
        try await waitUntil { tab.url == url && !tab.isLoading && tab.history.finishedLoads > finished }
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
        // Another address is always a new visit.
        try await load("https://example.com/autre", title: "Autre", in: tab)
        try await waitUntil { records.count == 3 }
    }

    @Test func `pages that are not web pages or files are never recorded`() async throws {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(blankPage("vide"))
        try await waitUntil { tab.url == blankPage("vide") && !tab.isLoading }
        tab.load(TestPages.url("locale"))
        try await waitUntil { tab.title == "locale" && !tab.isLoading && tab.history.finishedLoads == 2 }
        #expect(records.isEmpty)
    }

    @Test func `a page without history scope records nothing`() async throws {
        // Private window: the Space has no history.
        let privateManager = TabManager(websiteDataStore: .nonPersistent())
        let tab = try await open("https://example.com/", title: "Privé", in: privateManager)
        #expect(records.isEmpty)
        #expect(tab.title == "Privé")
    }

    @Test func `an address changed by the page is recorded once it settles`() async throws {
        let tab = try await open("https://app.example/", title: "Accueil")
        try await waitUntil { records.count == 1 }

        // A burst of `replaceState` only records the last address.
        clock.advance(5)
        _ = try await tab.loadedWebView.evaluateJavaScript("""
        for (let i = 0; i < 5; i++) { history.replaceState({}, '', '/recherche?q=' + i); }
        document.title = 'Recherche'; true
        """)
        try await waitUntil { records.count == 2 && !tab.history.hasPendingChange }
        #expect(records.map(\.urlKey) == ["app.example", "app.example/recherche?q=4"])
        #expect(records.last?.title == "Recherche")

        // A fragment alone is not a new page.
        clock.advance(120)
        _ = try await tab.loadedWebView.evaluateJavaScript("location.hash = 'section'; true")
        try await waitUntil { tab.url?.fragment == "section" }
        // The address change is looked at when it arrives: a fragment alone waits for nothing.
        #expect(!tab.history.hasPendingChange)
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
        // The title is looked at as soon as it changes.
        try await waitUntil { tab.title == "(1) Nouveau message" }
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
