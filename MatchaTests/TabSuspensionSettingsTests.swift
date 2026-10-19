import Foundation
@testable import Matcha
import Testing

/// “Free memory of inactive tabs after” setting (task 5.6).
struct TabSuspensionSettingsTests {
    private func emptyDefaults() -> UserDefaults {
        let name = "TabSuspensionSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func `options are offered in order with their durations`() {
        #expect(TabSuspensionDelay.allCases == [.fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours, .never])
        #expect(TabSuspensionDelay.allCases.map(\.duration) == [.seconds(900), .seconds(1800), .seconds(3600), .seconds(7200), nil])
    }

    @Test func `thirty minutes by default`() {
        #expect(BrowserSettings.tabSuspensionDelay == .thirtyMinutes)
        #expect(BrowserSettings.tabSuspensionDelay(in: emptyDefaults()) == .thirtyMinutes)
        let settings = TabSuspensionSettings.current(in: emptyDefaults())
        #expect(settings.delay == .seconds(1800))
        #expect(settings.checkInterval == .seconds(60))
    }

    @Test func `the stored number of minutes is read, never included`() {
        let defaults = emptyDefaults()
        defaults.set(120, forKey: BrowserSettings.Key.tabSuspensionDelay)
        #expect(BrowserSettings.tabSuspensionDelay(in: defaults) == .twoHours)
        defaults.set(0, forKey: BrowserSettings.Key.tabSuspensionDelay)
        #expect(BrowserSettings.tabSuspensionDelay(in: defaults) == .never)
        #expect(TabSuspensionSettings.current(in: defaults).delay == nil)
    }

    /// Launch arguments (“-tabSuspensionDelay 0”) arrive as text.
    @Test(arguments: [
        ("0", TabSuspensionDelay.never),
        ("15", .fifteenMinutes),
        ("60", .oneHour),
        ("7", .thirtyMinutes),
        ("abc", .thirtyMinutes)
    ])
    func `launch arguments are read and unknown values fall back`(text: String, expected: TabSuspensionDelay) {
        let defaults = emptyDefaults()
        defaults.set(text, forKey: BrowserSettings.Key.tabSuspensionDelay)
        #expect(BrowserSettings.tabSuspensionDelay(in: defaults) == expected)
    }

    @Test func `the test delay argument wins in Debug, checked every second`() {
        let defaults = emptyDefaults()
        defaults.set("0", forKey: BrowserSettings.Key.tabSuspensionDelay)
        defaults.set("3", forKey: TabSuspensionSettings.testDelayKey)
        let settings = TabSuspensionSettings.current(in: defaults)
        #expect(settings.delay == .seconds(3))
        #expect(settings.checkInterval == .seconds(1))
    }
}
