import Foundation
@testable import Matcha
import Testing
import WebKit

@MainActor
struct MiniCommandBarModelTests {
    private let engine = FakeSuggestionEngine()
    private let tab = BrowserTab(configuration: WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent()))
    private let settings = CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: true)

    private func makeModel() -> MiniCommandBarModel {
        MiniCommandBarModel(tab: tab, faviconService: FaviconService(directory: nil), suggestions: engine.provider())
    }

    @Test func `new search opens empty without rows`() {
        let model = makeModel()
        model.present(.newSearch, settings: settings)
        #expect(model.isPresented)
        #expect(model.text.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(model.editedTab == nil)
        #expect(model.submission(for: nil) == .ignore)
    }

    @Test func `editing the address shows it with copy url and asks nobody`() async throws {
        let url = blankPage("mini")
        tab.load(url)
        try await waitUntil { tab.url == url }
        let model = makeModel()

        model.present(.editAddress, settings: settings)
        await model.waitForPendingResults()
        #expect(model.text == url.absoluteString)
        #expect(model.rows.map(\.style) == [.openAddress, .action(.copyURL)])
        #expect(model.editedTab === tab)
        #expect(engine.requests.isEmpty)
        #expect(model.submission(for: nil) == .load(url))
        #expect(model.submission(for: model.rows[1].id) == .copyURL)
    }

    @Test func `editing without a page is a new search`() {
        let model = makeModel()
        model.present(.editAddress, settings: settings)
        #expect(model.mode == .newSearch)
        #expect(model.text.isEmpty)
    }

    @Test func `typed search lists the search then suggestions only`() async throws {
        engine.responses["swift"] = ["swift 6", "swiftui"]
        let model = makeModel()
        model.present(.newSearch, settings: settings)

        model.updateText("swift")
        #expect(model.rows.map(\.style) == [.search])
        await model.waitForPendingResults()
        #expect(model.rows.map(\.style) == [.search, .suggestion, .suggestion])
        #expect(model.selectedRowID == model.rows.first?.id)
        #expect(try model.submission(for: nil) == .load(#require(SearchEngine.google.searchURL(for: "swift"))))
    }

    @Test func `typed domain offers its search as second row`() throws {
        let model = makeModel()
        model.present(.newSearch, settings: settings)
        model.updateText("apple.com")
        #expect(model.rows.map(\.style) == [.openAddress, .searchAlternative])
        #expect(try model.submission(for: nil) == .load(#require(URL(string: "https://apple.com"))))
    }

    @Test func `suggestions setting off asks nobody`() async {
        let model = makeModel()
        var quiet = settings
        quiet.showsSearchSuggestions = false
        model.present(.newSearch, settings: quiet)
        model.updateText("swift")
        await model.waitForPendingResults()
        #expect(engine.requests.isEmpty)
        #expect(model.rows.map(\.style) == [.search])
    }

    @Test func `presenting again keeps the text and refocuses`() {
        let model = makeModel()
        model.present(.newSearch, settings: settings)
        model.updateText("pain")
        let request = model.focusRequest
        model.present(.newSearch, settings: settings)
        #expect(model.text == "pain")
        #expect(model.focusRequest == request + 1)
    }

    @Test func `dismiss forgets everything`() {
        let model = makeModel()
        model.present(.newSearch, settings: settings)
        model.updateText("pain")
        model.dismiss()
        #expect(!model.isPresented)
        #expect(model.text.isEmpty && model.rows.isEmpty && model.selectedRowID == nil)
        #expect(model.submission(for: nil) == .ignore)
    }
}
