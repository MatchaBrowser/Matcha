import Foundation

/// How this launch runs (audit R6): the app itself, the host app of the unit tests, or a Debug build launched by the
/// UI tests with their arguments (store in memory or named, downloads subfolder). The published app ignores those
/// arguments: they are read in Debug builds only. Pure type.
nonisolated enum TestEnvironment {
    /// Host app of the unit tests (XCTest sets this variable): same settings and container as the app, so nothing of
    /// the user's must be read or written.
    static func isUnitTestHost(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    /// Where to read the UI tests' launch arguments; nil in a Release build.
    static func arguments(_ defaults: UserDefaults = .standard) -> UserDefaults? {
        #if DEBUG
            defaults
        #else
            nil
        #endif
    }

    /// Nothing saved: unit tests, or UI tests' `-inMemoryStore YES`.
    static func usesInMemoryStore(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> Bool {
        isUnitTestHost(environment) || arguments(defaults)?.bool(forKey: BrowserSession.inMemoryStoreKey) == true
    }

    /// Store a UI test may empty at launch: a named store of its own, never the default one (SwiftData's `default`).
    static func isResettableStore(named name: String) -> Bool {
        !name.isEmpty && name != "default"
    }
}
