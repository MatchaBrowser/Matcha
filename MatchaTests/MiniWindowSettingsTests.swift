import Foundation
@testable import Matcha
import Testing

struct MiniWindowSettingsTests {
    private let testDefaults = TestDefaults("MiniWindowSettingsTests")

    @Test func `launch argument strings and missing values are read`() {
        let defaults = testDefaults.make()
        #expect(MiniWindowSettings.current(defaults).showsSearchSuggestions)
        #expect(MiniWindowSettings.current(defaults).searchEngine == BrowserSettings.searchEngine)

        // “-showsSearchSuggestions NO” arrives as text.
        defaults.set("NO", forKey: BrowserSettings.Key.showsSearchSuggestions)
        defaults.set("bing", forKey: BrowserSettings.Key.searchEngine)
        #expect(!MiniWindowSettings.current(defaults).showsSearchSuggestions)
        #expect(MiniWindowSettings.current(defaults).searchEngine == .bing)
    }
}
