import SwiftUI

/// History menu: homepage, reopening closed tabs (⇧⌘T, audit H2), back and forward for the front page, the tabs of the
/// account's other Macs (`SYNC.md` § 2.4), and the history window (⌘Y, task 5.5), disabled when a private window is
/// active (it has no history).
struct HistoryCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openWindow) private var openWindow
    /// Shortcuts chosen in Settings > Shortcuts.
    let shortcuts: MenuShortcutStore
    let otherMacs: OtherMacsTabs

    /// Longest tab title shown in the menu.
    private static let maximumTitleLength = 70

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
            otherMacsMenu
            Divider()
            Button("Show All History") { openWindow(id: MatchaApp.historyWindowID) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .showAllHistory))
                .disabled(windowActions?.isPrivate == true)
        }
    }

    /// A submenu per Mac, its tabs by Space; one opens in a new tab of the active window, as in the command bar.
    private var otherMacsMenu: some View {
        Menu {
            ForEach(otherMacs.macs) { mac in
                Menu {
                    ForEach(mac.spaces, id: \.spaceId) { space in
                        Section {
                            ForEach(Array(space.tabs.enumerated()), id: \.offset) { _, tab in
                                Button { openOtherMacTab(tab.url) } label: { Text(verbatim: Self.menuTitle(of: tab)) }
                            }
                        } header: {
                            Text(verbatim: space.name)
                        }
                    }
                } label: {
                    Text(verbatim: mac.name)
                }
            }
        } label: {
            Text("Tabs from Your Other Macs", comment: "History menu: submenu with the today tabs of the account's other Macs (sync)")
        }
        .disabled(otherMacs.macs.isEmpty || browsingTabs == nil || windowActions?.isPrivate == true)
    }

    private static func menuTitle(of tab: SyncDeviceTabsFields.Tab) -> String {
        let title = tab.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = title.isEmpty ? CommandText.displayURL(tab.url) : title
        return text.count > maximumTitleLength ? text.prefix(maximumTitleLength - 1) + "…" : text
    }

    private func openOtherMacTab(_ url: URL) {
        guard let tabManager = browsingTabs else {
            return
        }
        windowActions?.showTab(tabManager.newTab(url: url))
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
