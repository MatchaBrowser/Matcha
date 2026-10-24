import Foundation

/// Tabs of a single window, outside any Space (Arc's “This Window”): a tab dragged out of the sidebar opens a window
/// with only itself, and leaves its Space. Same profile, history and settings as the Space it came from (`space`); never
/// saved as such: “Move to…” puts them into a Space, closing the window closes them (⇧⌘T in their Space brings them
/// back), and quitting the app puts them back into their Space (`BrowserSession+WindowTabs`).
@MainActor
final class WindowTabs: Identifiable {
    let id = UUID()
    let tabManager: TabManager
    /// Space the tabs came from.
    private(set) weak var space: SpaceSession?
    /// Brings the window showing these tabs to the front (another window chose one of them); given by the window.
    var bringWindowToFront: (@MainActor () -> Void)?

    init(tabManager: TabManager, space: SpaceSession) {
        self.tabManager = tabManager
        self.space = space
    }

    /// Takes in `tab`, a today tab removed from its Space (same profile): same page, same web view.
    func take(_ tab: BrowserTab) {
        tabManager.attach(tab)
        tabManager.select(tab)
    }

    /// A copy of `tab` (a favorite or pinned tab, which stays in the sidebar), with its back and forward history.
    func takeCopy(of tab: BrowserTab) {
        tabManager.insertCopy(of: tab, after: nil, select: true)
    }

    /// Gives all the tabs to `target`, in their order, the selected one selected there; nil if there were none.
    /// Same profile: the tabs keep their page and history; otherwise they are recreated from their address, with the
    /// cookies of that profile.
    @discardableResult
    func move(to target: SpaceSession) -> BrowserTab? {
        let selectedID = tabManager.selectedTabID
        let sameProfile = target.openedProfileID == space?.openedProfileID
        var selected: BrowserTab?
        for tab in tabManager.todayTabs.reversed() {
            let moved: BrowserTab?
            if sameProfile {
                moved = tabManager.detach(tab)
                moved.map(target.tabManager.attach)
            } else {
                let url = tab.url
                tabManager.delete(tab)
                moved = target.tabManager.newTab(url: url, select: false)
            }
            if tab.id == selectedID {
                selected = moved
            }
        }
        return selected
    }

    /// The window closes: its tabs close, and ⇧⌘T in their Space brings them back.
    func close() {
        let tabs = tabManager.todayTabs
        tabManager.rememberClosed(tabs)
        if let group = tabManager.closedTabs.popLast() {
            space?.tabManager.closedTabs.append(group)
        }
        tabs.forEach { tabManager.delete($0) }
        tabManager.closePeek()
    }
}
