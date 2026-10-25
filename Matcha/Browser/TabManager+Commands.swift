import Foundation
import WebKit

/// Bulk actions on tabs: “Clear” for the today tabs, “Duplicate Tab”, “Close Other Tabs”.
extension TabManager {
    /// Closes all today tabs (“Clear” button). A window whose selected tab was one of them shows its empty page:
    /// no pinned tab or favorite gets selected, it would load a page by itself.
    func clearToday() {
        let cleared = todayTabs
        // ⇧⌘T brings them all back (audit H2).
        rememberClosed(cleared)
        let ids = Set(cleared.map(\.id))
        let emptied = viewers.filter { $0.selectedTabID.map(ids.contains) ?? false }
        cleared.forEach(discard)
        emptied.forEach { setSelection(nil, for: $0) }
    }

    /// Opens a copy of the tab right after it, with its history, and selects it.
    @discardableResult
    func duplicate(_ tab: BrowserTab) -> BrowserTab {
        insertCopy(of: tab, after: tab, select: true)
    }

    /// A copy of `tab`, a tab of this profile (here or elsewhere), with its history, among the today tabs after
    /// `anchor` (at the top without one).
    @discardableResult
    func insertCopy(of tab: BrowserTab, after anchor: BrowserTab?, select: Bool) -> BrowserTab {
        // Same configuration: same profile. The interaction state carries the back/forward history; that of a tab
        // without a web view (asleep, task 5.6; restored and never shown, review ON11) is its kept state.
        let copy = insertTab(configuration: tab.configuration, after: anchor, select: select)
        if let state = tab.webView?.interactionState ?? tab.savedInteractionState {
            copy.webView?.interactionState = state
        } else if let url = tab.url {
            copy.load(url)
        }
        return copy
    }

    /// Closes all today tabs except `tab` and its split; `tab` is selected, pinned tabs and favorites remain. ⇧⌘T
    /// brings them all back.
    func closeOtherTabs(than tab: BrowserTab) {
        select(tab)
        let kept = Set(layout.split(containing: tab.id)?.tabIDs ?? [tab.id])
        let others = todayTabs.filter { !kept.contains($0.id) }
        rememberClosed(others)
        others.forEach { delete($0) }
    }
}

extension TabManager {
    /// Moves the tab one step up (−1) or down (+1) in its list, without dragging (audit H3); false at the edge.
    @discardableResult
    func moveStep(_ tab: BrowserTab, by offset: Int) -> Bool {
        guard let destination = layout.stepDestination(of: tab.id, by: offset) else {
            return false
        }
        move(tab, to: destination)
        return true
    }

    func canMoveStep(_ tab: BrowserTab, by offset: Int) -> Bool {
        layout.stepDestination(of: tab.id, by: offset) != nil
    }
}
