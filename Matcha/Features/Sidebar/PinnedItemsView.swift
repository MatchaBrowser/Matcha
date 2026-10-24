import SwiftUI

/// Content of one level of the pinned items: tabs, splits (one row each) and folders, with the content of the
/// expanded folders, indented one step per level. Below a folder's row, its customization panel if it is open
/// in the window (full width of the sidebar, without indentation).
struct PinnedItemsView: View {
    static let indent = 14.0

    let items: [PinnedItem]
    /// Folder that contains these items, nil for the root of the pinned items.
    let parent: UUID?
    let depth: Int
    let tabManager: TabManager

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    var body: some View {
        ForEach(tabManager.layout.pinnedRows(items)) { row in
            let drop = SidebarRowDrop.pinned(row, in: parent)
            switch row {
            case let .tab(id, _):
                if let tab = tabManager.tab(withID: id) {
                    TabRowView(tab: tab, tabManager: tabManager, drop: drop)
                        .padding(.leading, CGFloat(depth) * Self.indent)
                }
            case let .split(group, _):
                SplitRowView(group: group, tabManager: tabManager, drop: drop)
                    .padding(.leading, CGFloat(depth) * Self.indent)
            case let .folder(folder, _):
                FolderRowView(folder: folder, tabManager: tabManager, drop: drop)
                    .padding(.leading, CGFloat(depth) * Self.indent)
                if let windowModel, windowModel.customizedFolderID == folder.id {
                    FolderCustomizationPanel(folder: folder, tabManager: tabManager) {
                        withMotion(.easeOut(duration: 0.2)) { windowModel.customizedFolderID = nil }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !folder.isCollapsed {
                    // AnyView: a view type cannot directly contain itself.
                    AnyView(PinnedItemsView(items: folder.items, parent: folder.id, depth: depth + 1, tabManager: tabManager))
                }
            }
        }
    }
}
