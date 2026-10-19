import SwiftUI

/// History menu: homepage, reopening closed tabs (⇧⌘T, audit H2), back and forward for the front page, and the
/// history window (⌘Y, task 5.5), disabled when a private window is active (it has no history).
struct HistoryCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openWindow) private var openWindow
    /// Shortcuts chosen in Settings > Shortcuts.
    let shortcuts: MenuShortcutStore

    /// Front page: the active mini window's, the peek if it is open, otherwise the selected tab.
    private var frontTab: BrowserTab? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow?.tab ?? tabManager?.frontTab
    }

    /// Tabs of the active browsing window; nil when a mini window is active.
    private var browsingTabs: TabManager? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow == nil ? tabManager : nil
    }

    /// “Reopen Closed Tabs” when the last closing took several (“Clear”).
    private var reopenTitle: String {
        (browsingTabs?.closedTabs.lastCount ?? 0) > 1
            ? String(localized: "Reopen Closed Tabs", comment: "History menu (⇧⌘T), after closing several tabs at once")
            : MenuShortcut.reopenClosedTab.title
    }

    var body: some Commands {
        CommandMenu("History") {
            Button("Homepage") { windowActions?.goHome?() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .homepage))
                .disabled(windowActions?.goHome == nil)
            Button(reopenTitle, action: reopenClosedTabs)
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .reopenClosedTab))
                .disabled(browsingTabs?.closedTabs.isEmpty != false)
            Divider()
            Button("Back") { frontTab?.goBack() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .back))
                .disabled(frontTab?.canGoBack != true)
            Button("Forward") { frontTab?.goForward() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .forward))
                .disabled(frontTab?.canGoForward != true)
            Divider()
            Button("Show All History") { openWindow(id: MatchaApp.historyWindowID) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .showAllHistory))
                .disabled(windowActions?.isPrivate == true)
        }
    }

    /// ⇧⌘T: the last closed tabs come back, the last one shown like a click in the sidebar.
    private func reopenClosedTabs() {
        guard let tabManager = browsingTabs else {
            return
        }
        tabManager.reopenClosedTabs()
        if let tab = tabManager.selectedTab {
            windowActions?.showTab(tab)
        }
    }
}
