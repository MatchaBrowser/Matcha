import Foundation

/// Restoring, saving, and exchanging tabs between Spaces.
extension TabManager {
    // MARK: Saving

    /// Puts back the saved tabs, without a web view: each creates it the first time it is shown.
    /// The most recently used tab is selected, without loading its page: it loads when the Space is
    /// shown (`loadSelectedTab`). A tab never used (imported, `lastActivity` at `distantPast`) is not
    /// selected: nothing loads by itself.
    func restore(tabs stored: [StoredTab], layout restoredLayout: SidebarLayout) {
        var restored: [BrowserTab] = []
        for entry in stored where restoredLayout.place(of: entry.id) != nil {
            let configuration = pages.makeConfiguration(websiteDataStore: websiteDataStore)
            let tab = BrowserTab(restoring: entry, configuration: configuration)
            register(tab)
            restored.append(tab)
        }
        var known = restoredLayout
        for id in restoredLayout.orderedTabIDs where tab(withID: id) == nil {
            known.remove(id)
        }
        updateLayout { $0 = known }
        let used = restored.filter { $0.lastActivity > .distantPast }
        restoreSelection(used.max { $0.lastActivity < $1.lastActivity }?.id)
    }

    /// Creates the web view of the displayed tabs (the selected tab and its split), to display them (Space
    /// shown, launch).
    func loadSelectedTab() {
        displayedTabs.forEach { $0.makeWebViewIfNeeded() }
    }

    /// What to save of each placed tab.
    func storedTabs() -> [StoredTab] {
        tabs.map { tab in
            StoredTab(
                id: tab.id,
                url: tab.url,
                title: tab.title,
                pinnedURL: tab.pinnedURL,
                pinnedTitle: tab.pinnedTitle,
                lastActivity: tab.lastActivity,
                interactionState: tab.savedInteractionState,
            )
        }
    }

    /// Keeps the navigation state of each loaded tab (app quitting).
    func captureInteractionStates() {
        tabs.forEach { $0.captureInteractionState() }
    }

    /// Appends `stored` at the end of the favorites, without a web view (import, task 7.1).
    func appendFavorites(_ stored: [StoredTab]) {
        for entry in stored {
            let configuration = pages.makeConfiguration(websiteDataStore: websiteDataStore)
            let tab = BrowserTab(restoring: entry, configuration: configuration)
            register(tab)
            updateLayout { $0.setPlace(tab.id, to: .favorite) }
        }
    }

    // MARK: Between Spaces

    /// Takes `adopted` as its favorites, the same tabs as the other Spaces of the profile (`ProfileFavorites`): in
    /// place of its copies of the same tabs, without those no longer among them (they stay wherever they went).
    func adoptFavorites(_ adopted: [BrowserTab]) {
        let ids = Set(adopted.map(\.id))
        for id in layout.favorites where !ids.contains(id) {
            unregister(id)
        }
        adopted.forEach(register)
        updateLayout { $0.setFavorites(adopted.map(\.id)) }
        dropMissingSelections()
    }

    /// Removes the tab from this Space without closing it, to send it to another Space of the same profile.
    @discardableResult
    func detach(_ tab: BrowserTab) -> BrowserTab? {
        guard self.tab(withID: tab.id) != nil else {
            return nil
        }
        moveSelection(awayFrom: tab) {
            updateLayout { $0.remove(tab.id) }
            unregister(tab.id)
        }
        return tab
    }

    /// Takes in a tab coming from another Space, at the top of the today tabs.
    func attach(_ tab: BrowserTab) {
        register(tab)
        tab.pinnedURL = nil
        tab.pinnedTitle = nil
        updateLayout { $0.insertToday(tab.id, at: 0) }
        if selectedTab == nil {
            setSelection(tab.id)
        }
    }
}
