import Foundation
import OSLog

/// A tab dragged from the sidebar of one window to that of another: it leaves its Space, or its window of its own tabs,
/// for the one it is dropped into.
extension BrowserSession {
    /// Tabs of the session: those of the Spaces, then those of the windows of their own tabs.
    var allTabManagers: [TabManager] {
        spaces.map(\.tabManager) + windowTabs.map(\.tabManager)
    }

    /// Brings tab `id`, from another Space or window of the session, into `target`, at the top of its today tabs; nil
    /// if no other one has it. Same profile: the tab keeps its page and its history. Other profile: it is recreated from
    /// its address, with the cookies of that profile. A favorite or a pinned tab dropped into a window of its own tabs
    /// stays in its sidebar: the window gets a copy.
    @discardableResult
    func bringTab(_ id: BrowserTab.ID, into target: TabManager) -> BrowserTab? {
        guard let source = allTabManagers.first(where: { $0 !== target && $0.tab(withID: id) != nil }),
              let tab = source.tab(withID: id)
        else {
            return nil
        }
        let keepsSource = windowTabs.contains { $0.tabManager === target } && source.place(of: tab) != .today
        let sameProfile = source.websiteDataStore === target.websiteDataStore
        let brought: BrowserTab
        if sameProfile, !keepsSource, let moved = source.detach(tab) {
            target.attach(moved)
            brought = moved
        } else if sameProfile {
            brought = target.insertCopy(of: tab, after: nil, select: false)
        } else {
            brought = target.newTab(url: tab.url ?? tab.pinnedURL, select: false)
            if !keepsSource {
                source.delete(tab)
            }
        }
        Logger.browser.info("Tab dropped into another window")
        return brought
    }
}
