import SwiftUI

/// Onglets épinglés et leurs dossiers, suivis d'une zone de dépôt.
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
