import SwiftUI

/// Puts a dragged tab, split or folder at a destination of the sidebar. A folder is accepted only among the pinned
/// items, a split outside favorites. A tab from the sidebar of another window (another Space, a window of its own
/// tabs) comes into this one and is shown there (`bringTab`); splits and folders stay in their window.
@MainActor
struct SidebarDropAction {
    let tabManager: TabManager
    /// Window of the sidebar; nil outside a browser window (tabs of other windows are then refused).
    let windowModel: WindowModel?

    func perform(_ item: SidebarDragItem, at target: SidebarDestination) -> Bool {
        switch item {
        case let .tab(id):
            if let tab = tabManager.tab(withID: id) {
                withMotion(.easeOut(duration: 0.15)) { tabManager.move(tab, to: target) }
            } else {
                return bringTab(id, to: target)
            }
        case let .folder(id):
            guard case .pinned = target else {
                return false
            }
            withMotion(.easeOut(duration: 0.15)) { tabManager.moveFolder(id, to: target) }
        case let .split(id):
            if case .favorites = target {
                return false
            }
            guard tabManager.layout.split(withID: id) != nil else {
                return false
            }
            withMotion(.easeOut(duration: 0.15)) { tabManager.moveSplit(id, to: target) }
        }
        return true
    }

    /// Tab of another window: it leaves it for this sidebar, at `target`, and this window shows it.
    private func bringTab(_ id: BrowserTab.ID, to target: SidebarDestination) -> Bool {
        guard let windowModel, let tab = windowModel.session.bringTab(id, into: tabManager) else {
            return false
        }
        withMotion(.easeOut(duration: 0.15)) { tabManager.move(tab, to: target) }
        // In this window, even if another one shows the same Space.
        windowModel.activate()
        TabActivation.activate(tab, in: tabManager)
        return true
    }
}
