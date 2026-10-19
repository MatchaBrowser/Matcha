import Foundation

/// Page targeted by the page commands: find (⌘F, ⌘G, ⇧⌘G; task 5.3), printing, PDF export and zoom (⌘P, ⌘+, ⌘-,
/// ⌘0; task 5.4). It is the active mini window's page, otherwise the front page of the active browsing window (the
/// peek if it is open, otherwise the selected tab, the active pane of a split). Nil without a loaded page: empty or
/// unloaded tab, no active browsing window (Settings), empty mini window.
@MainActor
enum FrontPage {
    static func page(miniWindowTab: BrowserTab?, tabManager: TabManager?) -> BrowserTab? {
        // An active mini window without a page never falls back to the browsing window behind it.
        guard let page = miniWindowTab ?? tabManager?.frontTab, page.hasURL, page.isLoaded else {
            return nil
        }
        return page
    }
}
