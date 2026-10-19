import SwiftUI

/// Help menu (audit H1), in place of the item without help that macOS adds: Matcha's site (⌘?), the shortcuts
/// (Settings > Shortcuts) and a problem report, opened in a tab of the active window (from a mini window: of the main
/// window).
struct HelpCommands: Commands {
    /// Matcha's pages.
    enum Page: String {
        case website = "https://github.com/MatchaBrowser/Matcha"
        case newIssue = "https://github.com/MatchaBrowser/Matcha/issues/new"
    }

    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Matcha Help") { open(.website) }
                .keyboardShortcut("?")
            Button("Keyboard Shortcuts") {
                SettingsSelection.shared.tab = .shortcuts
                openSettings()
            }
            Divider()
            Button("Report a Problem…") { open(.newIssue) }
        }
    }

    private func open(_ page: Page) {
        guard let url = URL(string: page.rawValue) else {
            return
        }
        _ = miniWindows.keyWindowID
        if miniWindows.keyWindow == nil, let tabManager, let windowActions {
            windowActions.showTab(tabManager.newTab(url: url))
        } else {
            miniWindows.openFromOtherApp([url], destination: .space)
        }
    }
}
