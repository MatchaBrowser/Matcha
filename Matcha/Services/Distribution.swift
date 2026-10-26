import Foundation

/// How this build of Matcha is distributed: Developer ID (scripts/release.sh, the CI image) or the Mac App Store
/// (target “Matcha App Store”, condition `APP_STORE`, review A1). In one place, so that the code of both stays compiled
/// and tested; only the private API of the web inspector is left out with `#if` (`WebInspection`).
nonisolated enum Distribution {
    #if APP_STORE
        static let isAppStore = true
    #else
        static let isAppStore = false
    #endif

    /// Extensions installed from a file travel without their package (review A2, choice B): no code is downloaded
    /// from the sync server; the other Mac installs the extension from its file, with the user's click.
    static var syncsExtensionPackages: Bool {
        !isAppStore
    }
}
