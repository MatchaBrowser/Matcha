import Foundation

/// Tabs closed by the user, brought back by History > Reopen Closed Tab (⇧⌘T, audit H2): page, back and forward
/// history, section and rank; the last group at once (all the tabs of “Clear”). Tabs without a page are not kept.
extension TabManager {
    /// Keeps `tabs` as one group, before they are removed.
    func rememberClosed(_ tabs: [BrowserTab]) {
        let group = tabs.compactMap { tab -> ClosedTab? in
            guard let place = layout.place(of: tab.id), tab.url != nil else {
                return nil
            }
            tab.captureInteractionState()
            let stored = StoredTab(
                id: UUID(),
                url: tab.url,
                title: tab.title,
                pinnedURL: tab.pinnedURL,
                pinnedTitle: tab.pinnedTitle,
                lastActivity: .now,
                interactionState: tab.savedInteractionState,
                fileReadAccess: tab.fileReadAccess,
            )
            return ClosedTab(stored: stored, place: place, todayIndex: layout.today.firstIndex(of: tab.id))
        }
        closedTabs.append(group)
    }

    /// Brings back the last closed group, at its places; its last tab is selected. Empty if there is none.
    @discardableResult
    func reopenClosedTabs() -> [BrowserTab] {
        guard let group = closedTabs.popLast() else {
            return []
        }
        // Today tabs by increasing rank: each one finds its neighbors already back.
        let ordered = group.sorted { ($0.todayIndex ?? .max) < ($1.todayIndex ?? .max) }
        let reopened = ordered.map { closed -> BrowserTab in
            let configuration = pages.makeConfiguration(websiteDataStore: websiteDataStore)
            let tab = BrowserTab(restoring: closed.stored, configuration: configuration, isSaved: false)
            register(tab)
            updateLayout { $0.insertToday(tab.id, at: min(closed.todayIndex ?? 0, $0.today.count)) }
            if closed.place != .today {
                updateLayout { $0.setPlace(tab.id, to: closed.place) }
            }
            return tab
        }
        // A restored tab keeps the identifier of its saved form: the last one closed is found again.
        if let last = group.last, reopened.contains(where: { $0.id == last.stored.id }) {
            setSelection(last.stored.id)
        }
        return reopened
    }
}
