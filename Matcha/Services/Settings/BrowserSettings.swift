import Foundation

/// Browser settings: keys in `UserDefaults` and default values.
/// Views read them with `@AppStorage(BrowserSettings.Key…)`.
nonisolated enum BrowserSettings {
    enum Key {
        static let searchEngine = "searchEngine"
        static let appearance = "appearance"
        static let confirmBeforeQuitting = "confirmBeforeQuitting"
        static let homePage = "homePage"
        static let newTabPage = "newTabPage"
        static let showsHomeButton = "showsHomeButton"
        static let addressBarPosition = "addressBarPosition"
        static let showsNavigationButtons = "showsNavigationButtons"
        static let showsSearchSuggestions = "showsSearchSuggestions"
        static let opensPinnedLinksInPeek = "opensPinnedLinksInPeek"
        static let tabSuspensionDelay = "tabSuspensionDelay"
        static let blocksAdsAndTrackers = "blocksAdsAndTrackers"
        static let externalLinkDestination = "externalLinkDestination"
        static let showsDeveloperTools = "showsDeveloperTools"
    }

    static let searchEngine = SearchEngine.defaultEngine
    static let appearance = AppearanceMode.system
    /// Off: tabs come back at the next launch (audit R7); some want it against a stray ⌘Q.
    static let confirmBeforeQuitting = false
    /// Homepage as typed; empty until one is chosen.
    static let homePage = ""
    static let newTabPage = NewTabPage.blank
    static let showsHomeButton = false
    static let addressBarPosition = AddressBarPosition.sidebar
    static let showsNavigationButtons = true
    /// Search engine suggestions in the command bar (never in a private window).
    static let showsSearchSuggestions = true
    /// Links from a favorite or a pinned tab to another site open in the peek (task 4.4), as in Arc; off by
    /// default: a plain click keeps its behavior until you choose otherwise.
    static let opensPinnedLinksInPeek = false
    /// Memory freed after 30 minutes without being displayed (task 5.6).
    static let tabSuspensionDelay = TabSuspensionDelay.thirtyMinutes
    /// Ad and tracker blocker (task 6.2), on as soon as lists are bundled.
    static let blocksAdsAndTrackers = true
    // Web developer tools (`WebInspection`): as in Safari, off by default; on in Debug.
    #if DEBUG
        static let showsDeveloperTools = true
    #else
        static let showsDeveloperTools = false
    #endif
    /// Links from other apps (task 8.2): in a mini window, like Little Arc.
    static let externalLinkDestination = ExternalLinkDestination.miniWindow

    /// Address of the homepage typed in the settings, interpreted as in the address bar;
    /// nil if it is empty.
    static func homeURL(from text: String, searchEngine: SearchEngine) -> URL? {
        AddressResolver(searchEngine: searchEngine).resolve(text)
    }

    /// Value of the alert before quitting in `defaults`, or its default value.
    static func confirmsBeforeQuitting(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.confirmBeforeQuitting) as? Bool ?? confirmBeforeQuitting
    }

    /// Value of the peek setting in `defaults`, or its default value. `bool(forKey:)` also reads the
    /// “YES” and “NO” of launch arguments (`as? Bool` ignores them).
    static func pinnedLinksOpenInPeek(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.opensPinnedLinksInPeek) == nil
            ? opensPinnedLinksInPeek
            : defaults.bool(forKey: Key.opensPinnedLinksInPeek)
    }

    /// Suspension delay of hidden tabs in `defaults` (minutes, a number or the text of a launch argument
    /// such as “-tabSuspensionDelay 0”), or its default value if the value is missing or is not an option.
    static func tabSuspensionDelay(in defaults: UserDefaults = .standard) -> TabSuspensionDelay {
        let stored = defaults.object(forKey: Key.tabSuspensionDelay)
        let minutes = (stored as? NSNumber)?.intValue ?? (stored as? String).flatMap { Int($0) }
        return minutes.flatMap(TabSuspensionDelay.init(rawValue:)) ?? tabSuspensionDelay
    }

    /// Value of the blocker setting in `defaults` (“YES” and “NO” of launch arguments included), or its
    /// default value; without settings (tests), the default value.
    static func blocksAdsAndTrackers(in defaults: UserDefaults?) -> Bool {
        guard let defaults, defaults.object(forKey: Key.blocksAdsAndTrackers) != nil else {
            return blocksAdsAndTrackers
        }
        return defaults.bool(forKey: Key.blocksAdsAndTrackers)
    }
}
