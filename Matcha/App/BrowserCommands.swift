import AppKit
import SwiftUI

/// The browser's menu commands and keyboard shortcuts, applied to the active window: a mini window (always checked
/// first: the window values are nil when a panel is active), otherwise the browsing window.
struct BrowserCommands: Commands {
    let miniWindows: MiniWindowManager
    /// Shortcuts chosen in Settings > Shortcuts.
    let shortcuts: MenuShortcutStore
    /// Tab shown by the Settings window (Help > Keyboard Shortcuts).
    let settingsSelection: SettingsSelection
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
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .newTab))
            .disabled(windowActions == nil && miniWindow == nil)

            Button("New Private Window") {
                openWindow(id: MatchaApp.privateWindowID)
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .newPrivateWindow))

            // Without its shortcut when the global one is the same: it would fire twice while the menu is open.
            Button("New Mini Window") {
                miniWindows.openNew(source: .menu)
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .newMiniWindow))

            Button("Open Location…") {
                if let mini = miniWindow {
                    mini.showCommandBar(.editAddress)
                } else {
                    windowActions?.editAddress()
                }
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .openLocation))
            .disabled(windowActions == nil && miniWindow == nil)

            Button(MenuShortcut.openFile.title, action: openFile)
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .openFile))

            Button("Open in Space") {
                if let mini = miniWindow {
                    miniWindows.openInSpace(mini) { openWindow(id: MatchaApp.browserWindowID) }
                }
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .openInSpace))
            .disabled(miniWindow?.tab.hasURL != true)
        }

        // Replaces “Close” (⌘W): ⌘W closes the tab (or the peek, or the mini window), ⇧⌘W the window,
        // as in Safari.
        CommandGroup(replacing: .saveItem) {
            Button(action: closeCommand) {
                closeTitle
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .closeTab))
            .disabled(miniWindow == nil && tabManager != nil && selectedTab == nil && windowActions?.isCommandBarPresented != true)

            Button("Close Window") {
                if let mini = miniWindow {
                    mini.close()
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .closeWindow))
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
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .copyURL))
            .disabled(miniWindow.map { !$0.tab.hasURL } ?? (windowActions?.copyURL == nil))
        }

        // Edit > Find, Spelling and Grammar, Substitutions, Transformations, Speech: macOS's standard commands
        // (audit H1). Find goes to the page's find bar (`PageFindResponder`).
        TextEditingCommands()

        CommandGroup(replacing: .sidebar) {
            Button(sidebarToggleTitle) {
                windowActions?.toggleSidebar()
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .toggleSidebar))
            .disabled(windowActions == nil)

            // View > “Show Downloads” (⌥⌘L), as in Safari. Disabled outside a browsing window (Settings, history)
            // and when a mini window is active: it has no sidebar.
            Button(downloadsToggleTitle) {
                windowActions?.toggleDownloads()
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .toggleDownloads))
            .disabled(windowActions == nil || miniWindow != nil)
        }

        CommandGroup(after: .toolbar) {
            let frontTab = frontTab
            Button(MenuShortcut.stopLoading.title) { self.frontTab?.stop() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .stopLoading))
                .disabled(frontTab?.isLoading != true)
            Button("Reload Page") { self.frontTab?.reload() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .reloadPage))
                .disabled(frontTab?.hasURL != true)
            Button(MenuShortcut.reloadFromOrigin.title) { self.frontTab?.reloadFromOrigin() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .reloadFromOrigin))
                .disabled(frontTab?.hasURL != true)
        }

        // File > Import From (task 7.1).
        ImportCommands()

        // File > Export as PDF…, Print…; View > zoom (task 5.4), after “Reload Page”.
        PageCommands(miniWindows: miniWindows, shortcuts: shortcuts)

        // The menus after View, in one group: a builder of commands takes at most 10 items before Xcode 27's SDK (the
        // CI's machines).
        Group {
            CommandMenu("Spaces") {
                if let windowActions {
                    ForEach(Array(windowActions.spaceNames.prefix(9).enumerated()), id: \.offset) { index, name in
                        Button(name) { windowActions.selectSpace(index) }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                    }
                    Divider()
                    Button("New Space") { windowActions.newSpace() }
                        .keyboardShortcut(shortcuts.keyboardShortcut(for: .newSpace))
                }
            }

            // Tabs menu: right after Spaces.
            TabCommands(miniWindows: miniWindows)

            // History menu: Homepage, Back, Forward, “Show All History” (task 5.5).
            HistoryCommands(miniWindows: miniWindows, shortcuts: shortcuts)

            // Help menu: Matcha's site and a problem report (audit H1).
            HelpCommands(miniWindows: miniWindows, settingsSelection: settingsSelection)
        }
    }

    /// ⌘O: the chosen files open in new tabs of the active window, or of the main window from a mini window.
    private func openFile() {
        let tabManager = miniWindow == nil ? tabManager : nil
        let windowActions = windowActions
        OpenFilePanel.choose { urls in
            if let tabManager, let windowActions {
                let tabs = urls.map { tabManager.newTab(url: $0) }
                tabs.last.map(windowActions.showTab)
            } else {
                miniWindows.openFromOtherApp(urls, destination: .space)
            }
        }
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
