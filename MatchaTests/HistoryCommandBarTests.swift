import Foundation
@testable import Matcha
import Testing
import WebKit

/// Historique dans la barre de commande (tâche 5.5) : celui du profil du Space affiché, ou de la mini-fenêtre.
@MainActor
struct HistoryCommandBarTests {
    private let session: BrowserSession
    private let windowModel: WindowModel
    private let engine = FakeSuggestionEngine()
    private let settings = CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: false)

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        windowModel = WindowModel(session: session, defaults: nil)
    }

    private func record(_ address: String, title: String, in space: SpaceSession) throws {
        let history = try #require(session.history)
        history.recordVisit(url: URL(string: address)!, title: title, profileID: space.record.profile?.id, spaceID: space.id)
    }

    private func historyTitles(_ rows: [CommandRow]) -> [String] {
        rows.filter { $0.style == .history }.map(\.title)
    }

    @Test func `the bar shows the history of the profile of the displayed space`() async throws {
        let history = try #require(session.history)
        let personal = session.spaces[0]
        let work = session.addProfile(named: "Travail")
        try record("https://perso.example.com/", title: "Exemple perso", in: personal)
        try record("https://travail.example.com/", title: "Exemple travail", in: work)
        let source = ProfileHistory(store: history) { [windowModel] in windowModel.space.record.profile?.id }
        let model = CommandBarModel(windowModel: windowModel, history: source, suggestions: engine.provider())

        model.newTab(settings)
        model.updateText("exemple")
        await model.waitForPendingResults()
        #expect(historyTitles(model.rows) == ["Exemple perso"])

        model.dismiss()
        windowModel.select(work)
        model.newTab(settings)
        model.updateText("exemple")
        await model.waitForPendingResults()
        #expect(historyTitles(model.rows) == ["Exemple travail"])
        let workPage = try #require(URL(string: "https://travail.example.com/"))
        #expect(model.rows.first { $0.style == .history }?.target == .open(workPage))
    }

    @Test func `an open tab hides the history of the same page`() async throws {
        let history = try #require(session.history)
        let space = session.spaces[0]
        try record("https://example.com/", title: "Exemple", in: space)
        let tab = space.tabManager.newTab()
        let url = try #require(URL(string: "https://www.example.com/"))
        tab.loadedWebView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<title>Exemple</title>")
        try await waitUntil { tab.url == url && !tab.isLoading }
        // Une autre page ouverte, pour que l'onglet sur example.com ne soit pas l'onglet affiché (exclu de la barre).
        space.tabManager.newTab()
        let model = CommandBarModel(
            windowModel: windowModel,
            history: ProfileHistory(store: history, profileID: space.record.profile?.id),
            suggestions: engine.provider(),
        )
        model.newTab(settings)
        model.updateText("exemple")
        await model.waitForPendingResults()
        #expect(historyTitles(model.rows).isEmpty)
        #expect(model.rows.contains {
            if case .tab = $0.style {
                $0.title == "Exemple"
            } else {
                false
            }
        })
    }

    @Test func `a mini window lists the history of its profile`() async throws {
        let history = try #require(session.history)
        let space = session.spaces[0]
        try record("https://example.com/docs", title: "Exemple docs", in: space)
        let tab = BrowserTab(configuration: WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent()))
        let model = MiniCommandBarModel(
            tab: tab,
            faviconService: FaviconService(directory: nil),
            history: ProfileHistory(store: history, profileID: space.record.profile?.id),
            suggestions: engine.provider(),
        )
        model.present(.newSearch, settings: settings)
        model.updateText("exemple")
        await model.waitForPendingResults()
        #expect(model.rows.map(\.style) == [.search, .history])
        #expect(model.rows.last?.title == "Exemple docs")
        #expect(try model.submission(for: model.rows.last?.id) == .load(#require(URL(string: "https://example.com/docs"))))

        // Autre profil : rien.
        let other = MiniCommandBarModel(
            tab: tab,
            faviconService: FaviconService(directory: nil),
            history: ProfileHistory(store: history, profileID: UUID()),
            suggestions: engine.provider(),
        )
        other.present(.newSearch, settings: settings)
        other.updateText("exemple")
        await other.waitForPendingResults()
        #expect(other.rows.map(\.style) == [.search])
    }
}
