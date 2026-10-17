import Foundation
@testable import Matcha
import Testing

/// État de la barre de commande : ouverture, saisie, sélection, résultats tardifs et annulation.
@MainActor
struct CommandBarModelTests {
    private let session: BrowserSession
    private let windowModel: WindowModel
    private let engine = FakeSuggestionEngine()
    private let blank = Self.settings(newTabPage: .blank)
    private let home = Self.settings(newTabPage: .homePage)

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        windowModel = WindowModel(session: session, defaults: nil)
    }

    private nonisolated static func settings(newTabPage: NewTabPage, engine: SearchEngine = .google) -> CommandBarSettings {
        CommandBarSettings(searchEngine: engine, newTabPage: newTabPage, homePage: "about:blank", showsSearchSuggestions: true)
    }

    private var tabManager: TabManager {
        windowModel.space.tabManager
    }

    /// Suggestions de `engine`, sans attendre.
    private func makeModel() -> CommandBarModel {
        CommandBarModel(windowModel: windowModel, suggestions: engine.provider(), now: { fixedNow })
    }

    private func ids(_ model: CommandBarModel) -> [String] {
        model.rows.map(\.id)
    }

    // MARK: Ouverture

    @Test func `command t opens the bar without creating a tab`() {
        let model = makeModel()
        // Fermée tant que rien ne l'ouvre : jamais d'ouverture d'elle-même.
        #expect(!model.isPresented)
        model.newTab(Self.settings(newTabPage: .blank, engine: .duckDuckGo))
        #expect(model.isPresented)
        #expect(model.mode == .newTab)
        #expect(model.text.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(model.selectedRowID == nil)
        #expect(model.focusRequest == 1)
        #expect(model.searchEngine == .duckDuckGo)
        #expect(tabManager.tabs.isEmpty)
    }

    @Test func `command t with a homepage creates the tab and edits it`() throws {
        let model = makeModel()
        model.newTab(home)
        let tab = try #require(tabManager.selectedTab)
        #expect(tabManager.tabs.count == 1)
        #expect(model.mode == .currentTab(tab.id))
        #expect(model.text == "about:blank")
        #expect(ids(model) == [CommandPrimaryRows.id, "action:copyURL"])
        #expect(model.rows.first?.title == "about:blank")
        #expect(model.selectedRowID == CommandPrimaryRows.id)
    }

    @Test func `command t with a homepage creates a tab even when the bar is open`() throws {
        let model = makeModel()
        model.newTab(blank)
        model.updateText("abc")
        model.newTab(home)
        let first = try #require(tabManager.selectedTab)
        #expect(model.mode == .currentTab(first.id))
        #expect(model.text == "about:blank")
        model.newTab(home)
        let second = try #require(tabManager.selectedTab)
        #expect(second !== first)
        #expect(tabManager.tabs.count == 2)
        #expect(model.mode == .currentTab(second.id))
        #expect(model.focusRequest == 3)
    }

    @Test func `command l without a tab falls back to new tab mode`() {
        let model = makeModel()
        model.editCurrentTab(home)
        #expect(model.isPresented)
        #expect(model.mode == .newTab)
        #expect(model.text.isEmpty)
        #expect(tabManager.tabs.isEmpty)
    }

    @Test func `command l prefills the address and offers copy url`() async {
        let url = blankPage("one")
        let tab = tabManager.newTab(url: url)
        let model = makeModel()
        model.editCurrentTab(blank)
        #expect(model.mode == .currentTab(tab.id))
        #expect(model.text == "about:blank?one")
        #expect(ids(model) == [CommandPrimaryRows.id, "action:copyURL"])
        #expect(model.rows.first?.target == .open(url))
        #expect(model.submission(for: nil) == .run(.open(url), mode: .currentTab(tab.id)))
        await model.waitForPendingResults()
        #expect(engine.requests.isEmpty)
    }

    @Test func `command l on an empty tab starts empty and return is ignored`() {
        let tab = tabManager.newTab()
        let model = makeModel()
        model.editCurrentTab(blank)
        #expect(model.mode == .currentTab(tab.id))
        #expect(model.text.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(model.submission(for: nil) == .ignore)
    }

    @Test func `opening again in the same mode keeps the text and asks for focus`() {
        let model = makeModel()
        model.newTab(blank)
        model.updateText("abc")
        let rows = model.rows
        model.newTab(blank)
        #expect(model.text == "abc")
        #expect(model.rows == rows)
        #expect(model.focusRequest == 2)

        tabManager.newTab(url: blankPage("one"))
        model.editCurrentTab(blank)
        model.updateText("xyz")
        model.editCurrentTab(blank)
        #expect(model.text == "xyz")
        #expect(model.focusRequest == 4)
    }

    @Test func `opening in the other mode resets the text`() {
        let tab = tabManager.newTab(url: blankPage("one"))
        let model = makeModel()
        model.editCurrentTab(blank)
        model.updateText("xyz")
        model.newTab(blank)
        #expect(model.mode == .newTab)
        #expect(model.text.isEmpty)
        #expect(model.rows.isEmpty)

        model.updateText("abc")
        model.editCurrentTab(blank)
        #expect(model.mode == .currentTab(tab.id))
        #expect(model.text == "about:blank?one")
        #expect(ids(model) == [CommandPrimaryRows.id, "action:copyURL"])
    }

    // MARK: Saisie et sélection

    @Test func `typing rebuilds the first row synchronously and selects it`() {
        let model = makeModel()
        model.newTab(blank)
        model.updateText("apple.com")
        #expect(ids(model) == [CommandPrimaryRows.id, CommandPrimaryRows.searchAlternativeID])
        #expect(model.rows.first?.style == .openAddress)
        #expect(model.selectedRowID == CommandPrimaryRows.id)
        model.moveSelection(by: 1)
        model.updateText("apple.co")
        #expect(model.rows.first?.title == "apple.co")
        #expect(model.selectedRowID == CommandPrimaryRows.id)
        #expect(model.selectedRow?.title == "apple.co")
    }

    @Test func `provider results are ranked once they arrive`() async {
        let other = tabManager.newTab(url: blankPage("one"))
        tabManager.newTab(url: blankPage("two"))
        engine.responses["blank"] = ["blank page", "blank"]
        let model = makeModel()
        model.newTab(blank)
        model.updateText("blank")
        #expect(ids(model) == [CommandPrimaryRows.id])
        await model.waitForPendingResults()
        #expect(ids(model) == [CommandPrimaryRows.id, "tab:\(other.id.uuidString)", "suggestion:blank page"])
        #expect(model.selectedRowID == CommandPrimaryRows.id)
    }

    @Test func `selection moves without wrapping`() {
        let model = makeModel()
        model.newTab(blank)
        model.moveSelection(by: 1)
        #expect(model.selectedRowID == nil)
        model.updateText("apple.com")
        model.moveSelection(by: -1)
        #expect(model.selectedRowID == CommandPrimaryRows.id)
        model.moveSelection(by: 1)
        #expect(model.selectedRowID == CommandPrimaryRows.searchAlternativeID)
        model.moveSelection(by: 5)
        #expect(model.selectedRowID == CommandPrimaryRows.searchAlternativeID)
        model.moveSelection(by: -10)
        #expect(model.selectedRowID == CommandPrimaryRows.id)
    }

    @Test func `selection survives late results by row id`() async throws {
        let other = tabManager.newTab(url: blankPage("one"))
        tabManager.newTab(url: blankPage("two"))
        engine.suspended = ["blank"]
        let model = makeModel()
        model.newTab(blank)
        model.updateText("blank")
        try await waitUntil { engine.isWaiting(for: "blank") }
        model.moveSelection(by: 1)
        #expect(model.selectedRowID == "tab:\(other.id.uuidString)")
        engine.resume("blank", with: ["blank page"])
        await model.waitForPendingResults()
        #expect(ids(model).last == "suggestion:blank page")
        #expect(model.selectedRowID == "tab:\(other.id.uuidString)")

        // Une suggestion gardée d'un texte précédent, sélectionnée, puis absente des nouvelles.
        engine.suspended = ["blank p"]
        model.updateText("blank p")
        model.moveSelection(by: 10)
        #expect(model.selectedRowID == "suggestion:blank page")
        try await waitUntil { engine.isWaiting(for: "blank p") }
        engine.resume("blank p", with: ["blank paper"])
        await model.waitForPendingResults()
        #expect(ids(model).last == "suggestion:blank paper")
        #expect(model.selectedRowID == CommandPrimaryRows.id)
    }

    @Test func `empty text has no rows; return opens an empty tab only in new tab mode`() {
        let model = makeModel()
        model.newTab(blank)
        #expect(model.submission(for: nil) == .openEmptyTab)
        model.updateText("   ")
        #expect(model.rows.isEmpty)
        #expect(model.submission(for: nil) == .openEmptyTab)

        tabManager.newTab(url: blankPage("one"))
        model.editCurrentTab(blank)
        model.updateText(" ")
        #expect(model.rows.isEmpty)
        #expect(model.submission(for: nil) == .ignore)
        model.dismiss()
        #expect(model.submission(for: nil) == .ignore)
    }
}
