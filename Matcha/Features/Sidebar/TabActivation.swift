import AppKit

/// Choosing a tab from the sidebar or the command bar: it is selected and its page
/// receives the keyboard.
@MainActor
enum TabActivation {
    static func activate(_ tab: BrowserTab, in tabManager: TabManager) {
        let window = NSApp.keyWindow
        tabManager.select(tab)
        // Leaves the field being edited (command bar, folder name).
        window?.makeFirstResponder(nil)
        // The tab's web view is only inserted into the window at the next render.
        Task { @MainActor in
            if let webView = tab.webView {
                webView.window?.makeFirstResponder(webView)
            }
        }
    }

    /// Gives the keyboard to the page of `tab` as soon as its web view is in a window (next render), unless
    /// someone took it in the meantime (bar reopened, folder field…).
    static func focusPage(of tab: BrowserTab) {
        Task { @MainActor in
            for _ in 0 ..< 10 {
                if let webView = tab.webView, let window = webView.window {
                    if window.firstResponder === window {
                        window.makeFirstResponder(webView)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
