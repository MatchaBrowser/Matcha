import Foundation

/// Moving a mini window's page into a Space (“Open in Space”).
@MainActor
enum MiniWindowHandOff {
    /// Puts the page at the top of the today tabs of `space`, on its own, and selects it; returns the Space's tab.
    /// Same profile: it is the same tab, with its web view (nothing is reloaded, the back/forward
    /// history and the page's state remain). Other profile: a new tab loads the address
    /// with that profile's cookies, and the mini window's page is released.
    /// Nil if the page has no address (nothing to open).
    @discardableResult
    static func move(_ tab: BrowserTab, profileID: UUID?, to space: SpaceSession) -> BrowserTab? {
        guard let url = tab.url else {
            return nil
        }
        let tabManager = space.tabManager
        guard space.record.profile?.id == profileID else {
            tab.unload(resettingTo: nil, title: nil)
            return tabManager.newTab(url: url)
        }
        // Same placement as a Peek opened as a tab (task 4.4): at the top, outside any split, selected.
        tabManager.insert(tab, after: nil, select: true)
        return tab
    }
}
