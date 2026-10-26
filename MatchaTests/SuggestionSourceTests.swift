import Foundation
@testable import Matcha
import Testing

/// Who suggests searches in the command bar (review A7): the search engine by default, or another one chosen in the
/// settings; the search itself stays with the search engine.
struct SuggestionSourceTests {
    private let testDefaults = TestDefaults("SuggestionSourceTests")

    @Test(arguments: SearchEngine.allCases)
    func `by default the search engine suggests`(searchEngine: SearchEngine) {
        #expect(BrowserSettings.searchSuggestionSource == .searchEngine)
        #expect(SuggestionSource.searchEngine.engine(for: searchEngine) == searchEngine)
        #expect(SuggestionSource.duckDuckGo.engine(for: searchEngine) == .duckDuckGo)
        #expect(SuggestionSource.bing.engine(for: searchEngine) == .bing)
        #expect(SuggestionSource.google.engine(for: searchEngine) == .google)
    }

    @Test func `the bar's settings carry the engine that suggests`() {
        let byDefault = CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: true)
        #expect(byDefault.suggestionEngine == .google)
        let chosen = CommandBarSettings(
            searchEngine: .google,
            newTabPage: .blank,
            homePage: "",
            showsSearchSuggestions: true,
            suggestionSource: .duckDuckGo,
        )
        #expect(chosen.searchEngine == .google)
        #expect(chosen.suggestionEngine == .duckDuckGo)
    }

    @Test func `a mini window reads the source from the settings`() {
        let defaults = testDefaults.make()
        defaults.set("bing", forKey: BrowserSettings.Key.searchEngine)
        #expect(MiniWindowSettings.current(defaults).suggestionEngine == .bing)
        defaults.set("duckDuckGo", forKey: BrowserSettings.Key.searchSuggestionSource)
        #expect(MiniWindowSettings.current(defaults).suggestionEngine == .duckDuckGo)
        defaults.set("inconnu", forKey: BrowserSettings.Key.searchSuggestionSource)
        #expect(MiniWindowSettings.current(defaults).suggestionEngine == .bing)
    }
}
