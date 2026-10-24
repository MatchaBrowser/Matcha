import SwiftUI

/// Accepts a dragged tab, split or folder and puts it at `destination` (`SidebarDropAction`).
struct SidebarDropModifier: ViewModifier {
    let tabManager: TabManager
    let destination: SidebarDestination
    @Binding var isTargeted: Bool

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    func body(content: Content) -> some View {
        content.dropDestination(for: SidebarDragItem.self) { items, _ in
            guard let item = items.first else {
                return false
            }
            return SidebarDropAction(tabManager: tabManager, windowModel: windowModel).perform(item, at: destination)
        } isTargeted: { targeted in
            withMotion(.easeOut(duration: 0.1)) { isTargeted = targeted }
        }
    }
}
