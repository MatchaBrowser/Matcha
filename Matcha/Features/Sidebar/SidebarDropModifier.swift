import SwiftUI

/// Accepts a dragged tab, split or folder and puts it at the destination computed from where it was dropped in the
/// view. A folder is accepted only among the pinned items, a split outside favorites. A tab from the sidebar of another
/// window (another Space, a window of its own tabs) comes into this one and is shown there (`bringTab`); splits and
/// folders stay in their window.
struct SidebarDropModifier: ViewModifier {
    let tabManager: TabManager
    @Binding var isTargeted: Bool
    let destination: (CGPoint) -> SidebarDestination

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    func body(content: Content) -> some View {
        content.dropDestination(for: SidebarDragItem.self) { items, location in
            guard let item = items.first else {
                return false
            }
            return drop(item, at: destination(location))
        } isTargeted: { targeted in
            withMotion(.easeOut(duration: 0.1)) { isTargeted = targeted }
        }
    }

    private func drop(_ item: SidebarDragItem, at target: SidebarDestination) -> Bool {
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
