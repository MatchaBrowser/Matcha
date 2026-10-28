import AppKit
import Foundation
@testable import Matcha
import Testing

struct BrowserSettingsTests {
    private let testDefaults = TestDefaults("BrowserSettingsTests")
    private func emptyDefaults() -> UserDefaults {
        testDefaults.make()
    }

    /// Off by default: tabs come back at the next launch (audit R7).
    @Test func `quitting confirmation can be turned on`() {
        let defaults = emptyDefaults()
        #expect(!BrowserSettings.confirmsBeforeQuitting(in: defaults))
        defaults.set(true, forKey: BrowserSettings.Key.confirmBeforeQuitting)
        #expect(BrowserSettings.confirmsBeforeQuitting(in: defaults))
        // Launch arguments (UI tests) give text.
        defaults.set("YES", forKey: BrowserSettings.Key.confirmBeforeQuitting)
        #expect(BrowserSettings.confirmsBeforeQuitting(in: defaults))
        defaults.set("NO", forKey: BrowserSettings.Key.confirmBeforeQuitting)
        #expect(!BrowserSettings.confirmsBeforeQuitting(in: defaults))
    }

    /// Hidden sidebar: gone by default, as in Arc; the stored values never change (settings already saved).
    @Test func `the hidden sidebar disappears by default`() {
        #expect(BrowserSettings.hiddenSidebarStyle == .hidden)
        #expect(HiddenSidebarStyle.allCases.map(\.rawValue) == ["hidden", "icons"])
    }

    /// A double click stays two clicks until the user chooses otherwise; the context menu renames.
    @Test func `tabs are not renamed by a double click by default`() {
        #expect(!BrowserSettings.renamesTabsOnDoubleClick)
    }

    @Test func `pinned links stay in their tab by default`() {
        #expect(!BrowserSettings.opensPinnedLinksInPeek)
        #expect(!BrowserSettings.pinnedLinksOpenInPeek(in: emptyDefaults()))
    }

    @Test func `pinned links in Peek follow the setting`() {
        let defaults = emptyDefaults()
        defaults.set(true, forKey: BrowserSettings.Key.opensPinnedLinksInPeek)
        #expect(BrowserSettings.pinnedLinksOpenInPeek(in: defaults))
        defaults.set(false, forKey: BrowserSettings.Key.opensPinnedLinksInPeek)
        #expect(!BrowserSettings.pinnedLinksOpenInPeek(in: defaults))
    }

    /// Launch arguments (“-opensPinnedLinksInPeek YES”) arrive as text.
    @Test(arguments: [("YES", true), ("NO", false)])
    func `pinned links in Peek read launch arguments`(text: String, expected: Bool) {
        let defaults = emptyDefaults()
        defaults.set(text, forKey: BrowserSettings.Key.opensPinnedLinksInPeek)
        #expect(BrowserSettings.pinnedLinksOpenInPeek(in: defaults) == expected)
    }

    @Test func `appearance modes map to AppKit appearances`() {
        #expect(AppearanceMode.system.appearanceName == nil)
        #expect(AppearanceMode.light.appearanceName == .aqua)
        #expect(AppearanceMode.dark.appearanceName == .darkAqua)
        #expect(AppearanceMode(rawValue: "dark") == .dark)
    }

    @Test func `search engines have display names`() {
        #expect(SearchEngine.allCases.map(\.name) == ["Google", "DuckDuckGo", "Bing"])
        #expect(SearchEngine(rawValue: "duckDuckGo") == .duckDuckGo)
    }

    @Test func `home page text is read like the address bar`() {
        #expect(BrowserSettings.homeURL(from: "", searchEngine: .google) == nil)
        #expect(BrowserSettings.homeURL(from: "  ", searchEngine: .google) == nil)
        #expect(BrowserSettings.homeURL(from: "apple.com", searchEngine: .google)?.absoluteString == "https://apple.com")
        #expect(BrowserSettings.homeURL(from: "about:blank", searchEngine: .google)?.absoluteString == "about:blank")
    }

    @Test func `new tabs open blank and the home button is hidden by default`() {
        #expect(BrowserSettings.newTabPage == .blank)
        #expect(!BrowserSettings.showsHomeButton)
        #expect(NewTabPage(rawValue: "homePage") == .homePage)
    }

    @Test func `address bar is in the sidebar with navigation buttons by default`() {
        #expect(BrowserSettings.addressBarPosition == .sidebar)
        #expect(BrowserSettings.showsNavigationButtons)
        #expect(AddressBarPosition(rawValue: "top") == .top)
    }

    @Test func `search suggestions are on by default`() {
        #expect(BrowserSettings.showsSearchSuggestions)
        #expect(BrowserSettings.Key.showsSearchSuggestions == "showsSearchSuggestions")
    }

    @Test func `command bar settings use the homepage only when asked and valid`() {
        func settings(_ page: NewTabPage, _ homePage: String) -> CommandBarSettings {
            CommandBarSettings(searchEngine: .duckDuckGo, newTabPage: page, homePage: homePage, showsSearchSuggestions: true)
        }
        #expect(settings(.blank, "apple.com").newTabHomeURL == nil)
        #expect(settings(.homePage, "").newTabHomeURL == nil)
        #expect(settings(.homePage, "  ").newTabHomeURL == nil)
        #expect(settings(.homePage, "apple.com").newTabHomeURL?.absoluteString == "https://apple.com")
        #expect(settings(.homePage, "apple.com").searchEngine == .duckDuckGo)
        #expect(settings(.homePage, "apple.com").showsSearchSuggestions)
    }
}
