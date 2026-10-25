import Foundation

/// Selection of each window (`TabViewer`): two windows can show this Space on different tabs. The tab actions apply to
/// the active viewer, that of the window in front; a tab closed or moved leaves the selection of every window.
extension TabManager {
    var selectedTabID: BrowserTab.ID? {
        activeViewer.selectedTabID
    }

    // MARK: Windows

    /// A window shows this Space for the first time: it takes the viewer left by a closed window (and its selection),
    /// otherwise a new one, on the active viewer's tab if no window shows it.
    func makeViewer() -> TabViewer {
        if let free = viewers.all.first(where: { !$0.isInUse }) {
            free.isInUse = true
            return free
        }
        let candidate = activeViewer.selectedTabID
        let isFree = layout.displayedTabIDs(selected: candidate).allSatisfy { displays.holder(of: $0) == nil }
        let viewer = TabViewer(selectedTabID: isFree ? candidate : nil)
        viewer.isInUse = true
        adopt(viewer)
        return viewer
    }

    /// The window of `viewer` closes: it is forgotten, unless no other viewer is left (the next window takes its
    /// selection).
    func releaseViewer(_ viewer: TabViewer) {
        setOnScreen(viewer, false)
        viewer.isInUse = false
        guard viewers.all.count > 1, viewers.contains(viewer) else {
            return
        }
        let others = viewers.all.filter { $0 !== viewer }
        if activeViewer === viewer, let heir = others.first(where: \.isOnScreen) ?? others.first {
            viewers.setActive(heir)
        }
        viewers.forget(viewer)
    }

    /// The tab actions now apply to `viewer` (its window comes to the front, shows this Space, or acts).
    func activate(_ viewer: TabViewer) {
        if activeViewer !== viewer, viewers.contains(viewer) {
            viewers.setActive(viewer)
        }
    }

    /// The window of `viewer` shows this Space (true), or no longer does. Shown, it takes its tabs from the other
    /// windows and creates their web views; hidden, the active viewer becomes that of another window showing it.
    func setOnScreen(_ viewer: TabViewer, _ isOnScreen: Bool) {
        viewer.isOnScreen = isOnScreen
        if isOnScreen {
            showHere(viewer)
        } else if activeViewer === viewer, let other = viewers.all.first(where: \.isOnScreen) {
            viewers.setActive(other)
        }
    }

    /// “Show Here”: the window of `viewer` takes the tabs it displays from the window that showed them.
    func showHere(_ viewer: TabViewer) {
        displays.claim(viewer.displayedTabIDs, for: viewer)
        displayedTabs(in: viewer).forEach { $0.makeWebViewIfNeeded() }
    }

    // MARK: Reading

    func displayedTabs(in viewer: TabViewer) -> [BrowserTab] {
        viewer.displayedTabIDs.compactMap(tab(withID:))
    }

    func displayedSplit(in viewer: TabViewer) -> SplitGroup? {
        viewer.selectedTabID.flatMap(layout.split(containing:))
    }

    /// True if the window of `viewer` shows the page of `id`: it displays it and no other window shows it.
    func shows(_ id: BrowserTab.ID, in viewer: TabViewer) -> Bool {
        displays.shows(id, in: viewer)
    }

    /// Viewer whose window shows `id`; otherwise the active viewer if it displays it, otherwise the first that does.
    func viewer(showing id: BrowserTab.ID) -> TabViewer? {
        if let holder = displays.holder(of: id), viewers.contains(holder) {
            return holder
        }
        if activeViewer.displayedTabIDs.contains(id) {
            return activeViewer
        }
        return viewers.all.first { $0.displayedTabIDs.contains(id) }
    }

    // MARK: Changing

    func setSelection(_ id: BrowserTab.ID?) {
        setSelection(id, for: activeViewer)
    }

    /// Selects `id` in the window of `viewer`, records its activity, takes the displayed tabs (its whole split) from
    /// the other windows and makes sure their web views exist.
    func setSelection(_ id: BrowserTab.ID?, for viewer: TabViewer) {
        // The Peek belongs to the displayed tab: displaying another one closes it (task 4.4), unless it is in another
        // window.
        if let peek, peek.sourceTabID != id, displays.holder(of: peek.sourceTabID).map({ $0 === viewer }) ?? true {
            closePeek()
        }
        // Tabs that leave the screen keep their navigation state.
        let leaving = displayedTabs(in: viewer)
        viewer.selectedTabID = id
        let shown = displayedTabs(in: viewer)
        for tab in leaving where !shown.contains(where: { $0 === tab }) {
            tab.captureInteractionState()
        }
        if let id {
            tab(withID: id)?.lastActivity = .now
        }
        displays.claim(shown.map(\.id), for: viewer)
        shown.forEach { $0.makeWebViewIfNeeded() }
    }

    /// Applies `change` to `tab`; in each window where it was selected, the selection moves to its neighbor in the
    /// split, otherwise (today tab) to the next today tab, or to the previous one if it was the last.
    func moveSelection(awayFrom tab: BrowserTab, during change: () -> Void) {
        moveSelection(awayFrom: [tab.id], preferring: layout.split(containing: tab.id)?.neighbor(of: tab.id), during: change)
    }

    /// Applies `change`; in each window whose selected tab is part of `ids`, the selection moves to `preferred` (its
    /// neighbor in a split, already on screen) if it is still placed. Otherwise, from a today tab, to the first today
    /// tab outside `ids` that followed it, otherwise to the last one that preceded it. Never to another pinned tab or
    /// favorite, which would load a page by itself: with no today tab left, or from a pinned tab or a favorite, the
    /// window shows its empty page.
    func moveSelection(awayFrom ids: Set<BrowserTab.ID>, preferring preferred: BrowserTab.ID? = nil, during change: () -> Void) {
        let today = layout.today
        let moving = viewers.all.compactMap { viewer -> SelectionMove? in
            guard let selected = viewer.selectedTabID, ids.contains(selected) else {
                return nil
            }
            return SelectionMove(viewer: viewer, todayIndex: today.firstIndex(of: selected))
        }
        change()
        for move in moving {
            setSelection(layout.nextSelection(from: move.todayIndex, in: today, leaving: ids, preferring: preferred), for: move.viewer)
        }
    }

    /// The window of `viewer` leaves the tabs `ids` (a tab and its split going to another window): it shows the next
    /// today tab, as if they were closed there, and the other windows don't change.
    func moveSelection(of viewer: TabViewer, awayFrom ids: Set<BrowserTab.ID>) {
        let today = layout.today
        let index = viewer.selectedTabID.flatMap { today.firstIndex(of: $0) }
        setSelection(layout.nextSelection(from: index, in: today, leaving: ids, preferring: nil), for: viewer)
    }

    /// Windows whose selected tab no longer exists in this Space show their empty page.
    func dropMissingSelections() {
        for viewer in viewers.all {
            if let id = viewer.selectedTabID, tab(withID: id) == nil {
                setSelection(nil, for: viewer)
            }
        }
    }
}

/// A window whose selected tab leaves, and where that tab was among the today tabs.
private struct SelectionMove {
    let viewer: TabViewer
    let todayIndex: Int?
}
