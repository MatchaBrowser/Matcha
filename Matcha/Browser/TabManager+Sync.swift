import Foundation

/// Changes received from another Mac (task 7.4, `SYNC.md` § 2.4).
extension TabManager {
    /// Takes back the saved tabs and layout, changed by sync. A tab already there keeps its web view; if it is not
    /// displayed and its address changed, it unloads and will load the new one the next time it is opened. A newly
    /// arrived tab is neither loaded nor selected. A displayed page does not change before the user's eyes: a
    /// displayed tab closed elsewhere stays there, in its place, until the user closes it.
    func reconcile(tabs stored: [StoredTab], layout newLayout: SidebarLayout) {
        let displayed = Set(displayedTabIDs)
        var target = newLayout
        for id in displayed where target.place(of: id) == nil {
            switch layout.place(of: id) {
            case .favorite: target.setPlace(id, to: .favorite)
            case .pinned: target.setPlace(id, to: .pinned)
            case .today: target.insertToday(id, at: layout.today.firstIndex(of: id) ?? 0)
            case nil: break
            }
        }
        for entry in stored where target.place(of: entry.id) != nil {
            if let tab = tab(withID: entry.id) {
                update(tab, from: entry, isDisplayed: displayed.contains(entry.id))
            } else {
                let configuration = pages.makeConfiguration(websiteDataStore: websiteDataStore)
                register(BrowserTab(restoring: entry, configuration: configuration))
            }
        }
        for tab in tabs where target.place(of: tab.id) == nil {
            discard(tab)
        }
        updateLayout { $0 = target }
        if let selectedTabID, tab(withID: selectedTabID) == nil {
            setSelection(nil)
        }
    }

    private func update(_ tab: BrowserTab, from entry: StoredTab, isDisplayed: Bool) {
        tab.pinnedURL = entry.pinnedURL
        tab.pinnedTitle = entry.pinnedTitle
        guard !isDisplayed, tab.url != entry.url || !tab.isLoaded && tab.title != entry.title else {
            return
        }
        tab.unload(resettingTo: entry.url, title: entry.title)
        faviconService.showCachedIcon(on: tab, host: entry.url?.host())
    }
}
