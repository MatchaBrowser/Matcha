import AppKit

/// App delegate: links opened by other apps, confirmation before quitting, Edit > Find on the pages.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Links from other apps, kept until the app is ready (`MatchaApp` gives them their handler).
    let incomingLinks = IncomingLinks()
    /// Edit > Find on the pages, given by `MatchaApp` (`AppEnvironment`).
    var pageFind: PageFindResponder?

    /// Web addresses and HTML files that macOS hands over to Matcha (task 8.2).
    func application(_: NSApplication, open urls: [URL]) {
        incomingLinks.receive(urls)
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        QuitConfirmation.shouldTerminate()
    }

    // MARK: Edit > Find

    /// Find commands that no view handled (`PageFindResponder`).
    @objc func performFindPanelAction(_ sender: Any?) {
        pageFind?.perform(tag: (sender as? NSMenuItem)?.tag ?? Int(NSFindPanelAction.showFindPanel.rawValue))
    }

    @objc func centerSelectionInVisibleArea(_: Any?) {
        pageFind?.jumpToSelection()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(performFindPanelAction(_:)):
            pageFind?.canPerform(tag: item.tag) ?? false
        case #selector(centerSelectionInVisibleArea(_:)):
            pageFind?.hasPage ?? false
        default:
            true
        }
    }
}
