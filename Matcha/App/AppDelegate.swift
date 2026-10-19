import AppKit

/// App delegate: links opened by other apps, confirmation before quitting.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Web addresses and HTML files that macOS hands over to Matcha (task 8.2).
    func application(_: NSApplication, open urls: [URL]) {
        IncomingLinks.shared.receive(urls)
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        QuitConfirmation.shouldTerminate()
    }
}
