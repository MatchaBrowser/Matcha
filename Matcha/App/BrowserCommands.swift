import AppKit
import SwiftUI

/// The browser's menu commands and keyboard shortcuts, applied to the active window: a mini window (always checked
/// first: the window values are nil when a panel is active), otherwise the browsing window.
struct BrowserCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openWindow) private var openWindow

    /// Active mini window: `keyWindowID` is read so the menu follows along, the window is read again on each action.
    private var miniWindow: MiniWindowController? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow
    }

    private var selectedTab: BrowserTab? {
        tabManager?.selectedTab
    }

    /// Front page: the active mini window's, the peek if it is open, otherwise the selected tab.
    private var frontTab: BrowserTab? {
        miniWindow?.tab ?? tabManager?.frontTab
    }

    /// Peek open (and no command bar): ⌘W closes it.
    private var isPeekOpen: Bool {
        tabManager?.peek != nil && windowActions?.isCommandBarPresented != true
    }

    private var closeTitle: Text {
        if miniWindow != nil {
            Text("Close Mini Window")
        } else if isPeekOpen {
            Text(PeekActions.closeTitle)
        } else {
            Text("Close Tab")
        }
    }

    private var sidebarToggleTitle: LocalizedStringKey {
        windowActions?.isSidebarVisible == false ? "Show Sidebar" : "Hide Sidebar"
    }

    private var downloadsToggleTitle: LocalizedStringKey {
        windowActions?.isDownloadsPanelShown == true ? "Hide Downloads" : "Show Downloads"
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                if let mini = miniWindow {
                    // A mini window has only one page: a new search replaces it.
                    mini.showCommandBar(.newSearch)
                } else {
                    windowActions?.newTab()
                }
            }
            .keyboardShortcut("t")
            .disabled(windowActions == nil && miniWindow == nil)

            Button("New Private Window") {
                openWindow(id: MatchaApp.privateWindowID)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            // No key equivalent: the global (configurable) shortcut already is one, and a shortcut shown here
            // would fire twice while the menu is open.
            Button("New Mini Window") {
                miniWindows.openNew(source: .menu)
            }

            Button("Open Location…") {
                if let mini = miniWindow {
                    mini.showCommandBar(.editAddress)
                } else {
                    windowActions?.editAddress()
                }
            }
            .keyboardShortcut("l")
            .disabled(windowActions == nil && miniWindow == nil)

            Button("Open in Space") {
                if let mini = miniWindow {
                    miniWindows.openInSpace(mini) { openWindow(id: MatchaApp.browserWindowID) }
                }
            }
            .keyboardShortcut("o")
            .disabled(miniWindow?.tab.hasURL != true)
        }

        // Replaces “Close” (⌘W): ⌘W closes the tab (or the peek, or the mini window), ⇧⌘W the window,
        // as in Safari.
        CommandGroup(replacing: .saveItem) {
            Button(action: closeCommand) {
                closeTitle
            }
            .keyboardShortcut("w")
            .disabled(miniWindow == nil && tabManager != nil && selectedTab == nil && windowActions?.isCommandBarPresented != true)

            Button("Close Window") {
                if let mini = miniWindow {
                    mini.close()
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        // In the Edit menu, right after Copy, Paste, etc.
        CommandGroup(after: .pasteboard) {
            // Same title as the command bar action.
            Button(CommandActionID.copyURL.title) {
                if let mini = miniWindow {
                    mini.copyURL()
                } else {
                    windowActions?.copyURL?()
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(miniWindow.map { !$0.tab.hasURL } ?? (windowActions?.copyURL == nil))
        }

        // Edit > Find (⌘F, ⌘G, ⇧⌘G).
        FindCommands(miniWindows: miniWindows)

        CommandGroup(replacing: .sidebar) {
            Button(sidebarToggleTitle) {
                windowActions?.toggleSidebar()
            }
            .keyboardShortcut("s")
            .disabled(windowActions == nil)

            // View > “Show Downloads” (⌥⌘L), as in Safari. Disabled outside a browsing window (Settings, history)
            // and when a mini window is active: it has no sidebar.
            Button(downloadsToggleTitle) {
                windowActions?.toggleDownloads()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(windowActions == nil || miniWindow != nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Reload Page") { frontTab?.reload() }
                .keyboardShortcut("r")
                .disabled(frontTab?.hasURL != true)
        }

        // File > Import From (task 7.1).
        ImportCommands()

        // File > Export as PDF…, Print…; View > zoom (task 5.4), after “Reload Page”.
        PageCommands(miniWindows: miniWindows)

        CommandMenu("Spaces") {
            if let windowActions {
                ForEach(Array(windowActions.spaceNames.prefix(9).enumerated()), id: \.offset) { index, name in
                    Button(name) { windowActions.selectSpace(index) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                }
                Divider()
                Button("New Space") { windowActions.newSpace() }
            }
        }

        // Tabs menu: right after Spaces.
        TabCommands(miniWindows: miniWindows)

        // History menu: Homepage, Back, Forward, “Show All History” (task 5.5).
        HistoryCommands(miniWindows: miniWindows)
    }

    /// ⌘W: the active mini window (its bar first), otherwise the command bar, the peek, the tab, or the window
    /// without tabs (settings).
    private func closeCommand() {
        if let mini = miniWindow {
            mini.closeCommand()
        } else if let windowActions, windowActions.isCommandBarPresented {
            // Command bar open: ⌘W closes only the bar, never the tab by reflex.
            windowActions.closeCommandBar()
        } else if let tabManager, tabManager.peek != nil {
            // Peek open: ⌘W closes only the peek.
            PeekActions.close(in: tabManager)
        } else if let tabManager {
            if let tab = tabManager.selectedTab {
                tabManager.close(tab)
            }
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}
