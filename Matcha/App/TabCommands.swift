import SwiftUI

/// Tabs menu (task 4.8), after the Spaces menu as in Arc: ⌃⇥ and ⌃⇧⇥ cycle through the tabs in sidebar order,
/// wrapping around; ⌘1 to ⌘8 select the first favorites then pinned tabs (listed under their title, like the
/// Spaces); ⌘9 the last tab. Inactive when a mini window is active, or without an active browsing window
/// (Settings).
struct TabCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var focusedTabManager
    @FocusedValue(\.windowActions) private var windowActions

    /// Tabs of the active browsing window; nil when a mini window is active (`keyWindowID` is read so the menu
    /// follows along, the window is read again on each action).
    private var tabManager: TabManager? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow == nil ? focusedTabManager : nil
    }

    var body: some Commands {
        CommandMenu("Tabs") {
            let tabManager = tabManager
            Button("Show Next Tab") { show(self.tabManager?.adjacentTab(forward: true)) }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(tabManager?.adjacentTab(forward: true) == nil)
            Button("Show Previous Tab") { show(self.tabManager?.adjacentTab(forward: false)) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(tabManager?.adjacentTab(forward: false) == nil)
            if let tabManager {
                let order = tabManager.sidebarOrder
                Divider()
                ForEach(Array(order.numbered.prefix(SidebarOrder.numberedShortcuts.count).enumerated()), id: \.offset) { index, item in
                    Button(tabManager.title(of: item)) { show(self.tabManager?.numberedTab(index + 1)) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Button("Show Last Tab") { show(self.tabManager?.lastSidebarTab) }
                    .keyboardShortcut("9")
                    .disabled(order.lastItem == nil)
            }
        }
    }

    private func show(_ tab: BrowserTab?) {
        if let tab {
            windowActions?.showTab(tab)
        }
    }
}
