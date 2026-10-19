import AppKit

/// App delegate: links opened by other apps, confirmation before quitting, Edit > Find on the pages.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Web addresses and HTML files that macOS hands over to Matcha (task 8.2).
    func application(_: NSApplication, open urls: [URL]) {
        IncomingLinks.shared.receive(urls)
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        QuitConfirmation.shouldTerminate()
    }

    // MARK: Edit > Find

    /// Find commands that no view handled (`PageFindResponder`).
    @objc func performFindPanelAction(_ sender: Any?) {
        PageFindResponder.perform(tag: (sender as? NSMenuItem)?.tag ?? Int(NSFindPanelAction.showFindPanel.rawValue))
    }

    @objc func centerSelectionInVisibleArea(_: Any?) {
        PageFindResponder.jumpToSelection()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(performFindPanelAction(_:)):
            PageFindResponder.canPerform(tag: item.tag)
        case #selector(centerSelectionInVisibleArea(_:)):
            PageFindResponder.hasPage
        default:
            true
        }
    }
}
