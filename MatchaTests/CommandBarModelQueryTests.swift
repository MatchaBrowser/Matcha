import Foundation
@testable import Matcha
import Testing

/// Barre de commande : quelles recherches partent, et quand elles sont abandonnées.
@MainActor
struct CommandBarModelQueryTests {
    private let session: BrowserSession
    private let windowModel: WindowModel
    private let engine = FakeSuggestionEngine()
    private let settings = CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: true)

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        windowModel = WindowModel(session: session, defaults: nil)
    }

    /// `sleep` nil : la vraie attente de 150 ms avant les suggestions.
    private func makeModel(
        in windowModel: WindowModel? = nil,
        history: (any HistorySource)? = nil,
        sleep: SearchSuggestionsProvider.Sleep? = { _ in },
    ) -> CommandBarModel {
        CommandBarModel(
            windowModel: windowModel ?? self.windowModel,
            history: history,
            suggestions: engine.provider(sleep: sleep),
            now: { fixedNow },
        )
    }

    @Test func `only the last text reaches the suggestions`() async throws {
        let model = makeModel(sleep: nil)
        model.newTab(settings)
        model.updateText("a")
        model.updateText("ab")
        model.updateText("abc")
        await model.waitForPendingResults()
        #expect(engine.requests == ["abc"])

        // « a », puis « ab » pendant l'attente de « a » (attente factice : aucun délai réel en jeu).
        let gate = GatedSleep()
        let gated = makeModel(sleep: { try await gate.sleep($0) })
        gated.newTab(settings)
        gated.updateText("a")
        try await waitUntil { gate.waitingCount == 1 }
        gated.updateText("ab")
        try await waitUntil { gate.waitingCount == 2 }
        gate.open()
        await gated.waitForPendingResults()
        #expect(engine.requests == ["abc", "ab"])
    }

    @Test func `a newer text cancels the request in flight`() async throws {
        engine.suspended = ["ab"]
        engine.responses["abc"] = ["abc def"]
        let model = makeModel()
        model.newTab(settings)
        model.updateText("ab")
        try await waitUntil { engine.isWaiting(for: "ab") }
        model.updateText("abc")
        engine.resume("ab", with: ["ab suggestion"])
        await model.waitForPendingResults()
        #expect(engine.requests == ["ab", "abc"])
        #expect(model.rows.map(\.title) == ["abc", "abc def"])
    }

    @Test func `suggestions are never requested for the untouched address or in private windows`() async {
        windowModel.space.tabManager.newTab(url: blankPage("one"))
        let model = makeModel()
        model.editCurrentTab(settings)
        await model.waitForPendingResults()

        let privateWindow = WindowModel(session: BrowserSession.makePrivate(), defaults: nil)
        let privateModel = makeModel(in: privateWindow)
        privateModel.newTab(settings)
        privateModel.updateText("pain au levain")
        await privateModel.waitForPendingResults()
        #expect(privateModel.rows.map(\.id) == [CommandPrimaryRows.id])
        #expect(engine.requests.isEmpty)
    }

    @Test func `the suggestions setting reaches the model`() async {
        let off = CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: false)
        let silent = makeModel()
        silent.newTab(off)
        silent.updateText("pain au levain")
        await silent.waitForPendingResults()
        #expect(engine.requests.isEmpty)

        let model = makeModel()
        model.newTab(settings)
        model.updateText("pain au levain")
        await model.waitForPendingResults()
        #expect(engine.requests == ["pain au levain"])
    }

    @Test func `settings changed while the bar is open apply at once`() async throws {
        let off = CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: false)
        engine.responses["pain"] = ["pain perdu"]
        let model = makeModel()
        model.newTab(settings)
        model.updateText("pain")
        await model.waitForPendingResults()
        #expect(model.rows.map(\.title) == ["pain", "pain perdu"])

        // Suggestions coupées barre ouverte : les reçues disparaissent, plus rien ne part.
        model.apply(off)
        await model.waitForPendingResults()
        #expect(model.rows.map(\.title) == ["pain"])
        model.updateText("pain au levain")
        await model.waitForPendingResults()
        #expect(engine.requests == ["pain"])

        // Moteur changé barre ouverte, y compris par une nouvelle ouverture dans le même mode.
        let duckDuckGo = CommandBarSettings(searchEngine: .duckDuckGo, newTabPage: .blank, homePage: "", showsSearchSuggestions: true)
        model.newTab(duckDuckGo)
        await model.waitForPendingResults()
        #expect(model.text == "pain au levain")
        #expect(model.searchEngine == .duckDuckGo)
        #expect(engine.requests == ["pain", "pain au levain"])
        let expected = try #require(SearchEngine.duckDuckGo.searchURL(for: "pain au levain"))
        #expect(model.rows.first?.target == .open(expected))
    }

    @Test func `history rows appear when a source provides them`() async throws {
        let site = try #require(URL(string: "https://example.com/"))
        let source = FakeHistory(entries: [HistoryEntry(url: site, title: "Example Domain", visitCount: 4, lastVisit: fixedNow)])
        let model = makeModel(history: source)
        model.newTab(settings)
        model.updateText("exa")
        await model.waitForPendingResults()
        #expect(model.rows.map(\.id) == [CommandPrimaryRows.id, "history:example.com"])
        #expect(model.rows.last?.style == .history)
        #expect(model.rows.last?.target == .open(site))
        #expect(source.requests.map(\.text) == ["exa"])
    }

    @Test func `dismiss cancels pending work and clears the state`() async throws {
        engine.suspended = ["pain"]
        let model = makeModel()
        model.newTab(settings)
        model.updateText("pain")
        try await waitUntil { engine.isWaiting(for: "pain") }
        model.dismiss()
        #expect(!model.isPresented)
        #expect(model.mode == .newTab)
        #expect(model.text.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(model.selectedRowID == nil)
        #expect(model.focusRequest == 1)

        engine.resume("pain", with: ["pain perdu"])
        await model.waitForPendingResults()
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.rows.isEmpty)
        model.updateText("ignored")
        #expect(model.text.isEmpty)
        #expect(model.rows.isEmpty)
    }
}
