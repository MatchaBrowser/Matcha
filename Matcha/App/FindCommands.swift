import SwiftUI

/// Edit > Find submenu (task 5.3), as in Safari: “Find…” (⌘F), “Find Next” (⌘G), “Find Previous” (⇧⌘G), on the
/// page of the active window (`FrontPage`). It takes the place of the standard find commands (`.textEditing`, empty
/// today): never two ⌘F. A page that keeps ⌘F or ⌘G for itself (online editor) comes first, as in Safari: WebKit
/// sends it the shortcuts first.
struct FindCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    @FocusedValue(\.windowActions) private var windowActions

    /// Active mini window: `keyWindowID` is read so the menu follows along, the window is read again on each action.
    private var miniWindow: MiniWindowController? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow
    }

    private var page: BrowserTab? {
        FrontPage.page(miniWindowTab: miniWindow?.tab, tabManager: tabManager)
    }

    var body: some Commands {
        CommandGroup(replacing: .textEditing) {
            Menu("Find") {
                let page = page
                Button("Find…", action: showFindBar)
                    .keyboardShortcut("f")
                    .disabled(page == nil)
                // ⌘G and ⇧⌘G reopen the closed bar, without giving it keyboard focus.
                Button("Find Next") { self.page?.find.findNext() }
                    .keyboardShortcut("g")
                    .disabled(page?.find.hasQuery != true)
                Button("Find Previous") { self.page?.find.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(page?.find.hasQuery != true)
            }
        }
    }

    /// ⌘F: the open command bar closes first (only one text entry at a time), then the find bar opens, or stays
    /// open, and its field takes keyboard focus, with its text selected.
    private func showFindBar() {
        guard let page else {
            return
        }
        if let mini = miniWindow {
            if mini.commandBar.isPresented {
                mini.cancelCommandBar()
            }
        } else if let windowActions, windowActions.isCommandBarPresented {
            windowActions.closeCommandBar()
        }
        page.find.present()
    }
}
