import Foundation
import OSLog

/// History window (task 5.5): its profile and the opening of its rows in the main window. The mini window manager
/// already holds the link with the main window and its displayed Space.
extension MiniWindowManager {
    /// Profile whose visits the history window shows: that of the Space displayed by the main window (closed: the
    /// last one displayed), as for a new mini window; never a private window.
    var historyProfile: ProfileRecord? {
        displayedSpace.record.profile
    }

    /// Opens `urls` in new tabs, at the top of the today tabs of the displayed Space (if it belongs to profile
    /// `profileID`, otherwise the first Space of that profile), in their order; the first is selected. The main
    /// window comes to the front, reopened if needed by `openMainWindow`.
    func openFromHistory(_ urls: [URL], profileID: UUID?, openMainWindow: () -> Void) {
        let space = defaultTarget(profileID: profileID)
        // Each new tab goes to the top: the first is opened last.
        let tabs = urls.reversed().map { space.tabManager.newTab(url: $0, select: false) }
        guard let first = tabs.last else {
            return
        }
        space.tabManager.select(first)
        reveal(first, in: space, openMainWindow: openMainWindow)
        Logger.history.info("\(urls.count, privacy: .public) pages ouvertes depuis l'historique")
    }
}
