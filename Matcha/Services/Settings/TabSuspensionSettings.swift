import Foundation

/// Suspension settings read at each check: delay (nil: never) and interval between two checks.
nonisolated struct TabSuspensionSettings: Equatable, Sendable {
    /// One check per minute: a tab is suspended at most one minute after its delay.
    static let defaultCheckInterval = Duration.seconds(60)
    /// UI test launch argument, in Debug only: delay in seconds (it overrides the setting, “Never” included),
    /// checked every second.
    static let testDelayKey = "tabSuspensionDelaySeconds"

    let delay: Duration?
    let checkInterval: Duration

    static func current(in defaults: UserDefaults = .standard) -> Self {
        #if DEBUG
            if defaults.object(forKey: testDelayKey) != nil {
                return Self(delay: .seconds(max(1, defaults.integer(forKey: testDelayKey))), checkInterval: .seconds(1))
            }
        #endif
        return Self(delay: BrowserSettings.tabSuspensionDelay(in: defaults).duration, checkInterval: defaultCheckInterval)
    }
}
