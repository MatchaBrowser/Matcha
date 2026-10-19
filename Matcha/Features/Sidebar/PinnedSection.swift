import SwiftUI

/// Pinned tabs and their folders, followed by a drop zone.
struct PinnedSection: View {
    let tabManager: TabManager

    var body: some View {
        let items = tabManager.layout.pinned
        PinnedItemsView(items: items, parent: nil, depth: 0, tabManager: tabManager)
        SidebarDropZone(
            tabManager: tabManager,
            destination: .pinned(folder: nil, index: items.count),
            label: items.isEmpty ? "Pinned" : nil,
            restingHeight: items.isEmpty ? 6 : 4,
        )
        .accessibilityIdentifier("pinnedDropZone")
    }
}
