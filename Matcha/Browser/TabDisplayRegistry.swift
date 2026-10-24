import Foundation
import Observation

/// Which window shows each tab: a web view has only one parent, so a tab selected in several windows is shown by one
/// of them, and the others show “Open in Another Window”. The last window that showed it wins (selection, Space shown,
/// “Show Here”); if it no longer shows it, the first other window that does. Shared by all the Spaces of a session: a
/// profile's favorites belong to several of them.
@MainActor
@Observable
final class TabDisplayRegistry {
    /// Viewer that last showed each tab.
    private var claims: [BrowserTab.ID: TabViewer.ID] = [:]
    @ObservationIgnored private var viewers: [WeakTabViewer] = []

    private struct WeakTabViewer {
        weak var viewer: TabViewer?
    }

    func register(_ viewer: TabViewer) {
        viewers = viewers.filter { $0.viewer != nil && $0.viewer !== viewer } + [WeakTabViewer(viewer: viewer)]
    }

    /// Viewer whose window shows `id`; nil if no window on screen displays it.
    func holder(of id: BrowserTab.ID) -> TabViewer? {
        let showing = viewers.compactMap(\.viewer).filter { $0.isOnScreen && $0.displayedTabIDs.contains(id) }
        return showing.first { $0.id == claims[id] } ?? showing.first
    }

    /// `viewer` shows `ids` from now on, taking them from the windows that showed them.
    func claim(_ ids: [BrowserTab.ID], for viewer: TabViewer) {
        for id in ids where claims[id] != viewer.id {
            claims[id] = viewer.id
        }
    }

    /// `id` was closed.
    func forget(_ id: BrowserTab.ID) {
        if claims[id] != nil {
            claims[id] = nil
        }
    }

    /// True if `viewer` displays `id` and no other window shows it.
    func shows(_ id: BrowserTab.ID, in viewer: TabViewer) -> Bool {
        guard viewer.displayedTabIDs.contains(id) else {
            return false
        }
        return holder(of: id).map { $0 === viewer } ?? true
    }
}
