import Foundation
import WebKit

/// Bulk actions on tabs: “Clear” for the today tabs, “Duplicate Tab”, “Close Other Tabs”.
extension TabManager {
    /// Closes all today tabs (“Clear” button). If the selected tab was one of them, the selection moves
    /// to the last remaining tab of the sidebar.
    func clearToday() {
        let cleared = todayTabs
        let selectionCleared = cleared.contains { $0.id == selectedTabID }
        cleared.forEach(discard)
        if selectionCleared {
            setSelection(layout.orderedTabIDs.last)
        }
    }

    /// Opens a copy of the tab right after it, with its history, and selects it.
    @discardableResult
    func duplicate(_ tab: BrowserTab) -> BrowserTab {
        // Same configuration: same profile. The interaction state carries the back/forward history; that of a
        // sleeping tab (task 5.6) is its kept state.
        let copy = insertTab(configuration: tab.configuration, after: tab, select: true)
        let suspendedState = tab.suspension.isSuspended ? tab.savedInteractionState : nil
        if let state = tab.webView?.interactionState ?? suspendedState {
            copy.webView?.interactionState = state
        } else if let url = tab.url {
            copy.load(url)
        }
        return copy
    }

    /// Closes all today tabs except `tab` and its split; `tab` is selected, pinned tabs and favorites remain.
    func closeOtherTabs(than tab: BrowserTab) {
        select(tab)
        let kept = Set(layout.split(containing: tab.id)?.tabIDs ?? [tab.id])
        for other in todayTabs where !kept.contains(other.id) {
            close(other)
        }
    }
}
