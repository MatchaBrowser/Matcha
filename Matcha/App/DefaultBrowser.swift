import AppKit
import OSLog

/// This Mac's default browser (task 8.3). macOS asks for confirmation before the change.
@MainActor
enum DefaultBrowser {
    /// True if Matcha opens this Mac's web links.
    static var isMatcha: Bool {
        guard let page = URL(string: "https://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: page) else {
            return false
        }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Makes Matcha the default browser, for `http` then `https`; true if it is afterwards (the user can decline
    /// in macOS's prompt).
    @discardableResult
    static func makeMatcha() async -> Bool {
        for scheme in ["http", "https"] {
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            } catch {
                Logger.app
                    .notice(
                        "Default browser unchanged (\(scheme, privacy: .public)): \(error.logSummary, privacy: .public)",
                    )
                return isMatcha
            }
        }
        return isMatcha
    }
}
