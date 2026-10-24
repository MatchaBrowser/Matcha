import Foundation
import Observation

/// A browser window's view of a Space: the tab it selected there. Each window has one per Space it has shown, so two
/// windows can show the same Space on different tabs; the Space's `TabManager` acts for the active one, the viewer of
/// the window in front (`TabManager.activeViewer`). Made and released by the `TabManager` only.
@MainActor
@Observable
final class TabViewer: Identifiable {
    let id = UUID()
    /// Selected tab: shown in the window, or shown by another window (`TabDisplayRegistry`).
    var selectedTabID: BrowserTab.ID?
    /// Its window is open and shows this Space.
    var isOnScreen = false
    /// Held by an open window; a viewer left by a closed window keeps its selection for the next one.
    @ObservationIgnored var isInUse = false
    /// Space whose tabs it shows (`TabManager.adopt`).
    @ObservationIgnored weak var tabManager: TabManager?

    init(selectedTabID: BrowserTab.ID? = nil) {
        self.selectedTabID = selectedTabID
    }

    /// Tabs this viewer displays: its selected tab's split, otherwise the tab alone.
    var displayedTabIDs: [BrowserTab.ID] {
        tabManager?.layout.displayedTabIDs(selected: selectedTabID) ?? []
    }
}
