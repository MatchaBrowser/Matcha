import SwiftUI

/// History menu: homepage, back and forward for the front page, and the history window (⌘Y, task 5.5), disabled
/// when a private window is active (it has no history).
struct HistoryCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openWindow) private var openWindow

    /// Front page: the active mini window's, the peek if it is open, otherwise the selected tab.
    private var frontTab: BrowserTab? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow?.tab ?? tabManager?.frontTab
    }

    var body: some Commands {
        CommandMenu("History") {
            Button("Homepage") { windowActions?.goHome?() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(windowActions?.goHome == nil)
            Divider()
            Button("Back") { frontTab?.goBack() }
                .keyboardShortcut("[")
                .disabled(frontTab?.canGoBack != true)
            Button("Forward") { frontTab?.goForward() }
                .keyboardShortcut("]")
                .disabled(frontTab?.canGoForward != true)
            Divider()
            Button("Show All History") { openWindow(id: MatchaApp.historyWindowID) }
                .keyboardShortcut("y")
                .disabled(windowActions?.isPrivate == true)
        }
    }
}
