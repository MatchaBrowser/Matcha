import Foundation

/// Safari extension of an installed app (task 6.4): an `.appex` at the `com.apple.Safari.web-extension` extension
/// point, with its `manifest.json`. Matcha loads it in place (`WKWebExtension(appExtensionBundle:)`): the app's updates
/// (App Store) update it.
nonisolated struct SafariAppExtension: Equatable, Identifiable, Sendable {
    let appURL: URL
    let appName: String
    let extensionURL: URL
    let bundleIdentifier: String
    /// Name of the extension given by its manifest, otherwise that of the app (the name of the `.appex` is often
    /// generic: “Safari Extension”).
    let displayName: String

    var id: String {
        bundleIdentifier
    }
}
