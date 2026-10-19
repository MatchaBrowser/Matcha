import Foundation
@testable import Matcha
import Testing

struct MiniWindowSettingsTests {
    @Test func `launch argument strings and missing values are read`() throws {
        let defaults = try #require(UserDefaults(suiteName: "MiniWindowSettingsTests"))
        defaults.removePersistentDomain(forName: "MiniWindowSettingsTests")
        #expect(MiniWindowSettings.current(defaults).showsSearchSuggestions)
        #expect(MiniWindowSettings.current(defaults).searchEngine == BrowserSettings.searchEngine)

        // “-showsSearchSuggestions NO” arrives as text.
        defaults.set("NO", forKey: BrowserSettings.Key.showsSearchSuggestions)
        defaults.set("bing", forKey: BrowserSettings.Key.searchEngine)
        #expect(!MiniWindowSettings.current(defaults).showsSearchSuggestions)
        #expect(MiniWindowSettings.current(defaults).searchEngine == .bing)
        defaults.removePersistentDomain(forName: "MiniWindowSettingsTests")
    }
}
