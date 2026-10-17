import SwiftUI

/// Contenu d'un niveau des épinglés : onglets et dossiers, avec le contenu des dossiers dépliés,
/// indenté d'un cran par niveau.
struct PinnedItemsView: View {
    static let indent = 14.0

    let items: [PinnedItem]
    /// Dossier qui contient ces éléments, nil pour la racine des épinglés.
    let parent: UUID?
    let depth: Int
    let tabManager: TabManager

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let destination = SidebarDestination.pinned(folder: parent, index: index)
            switch item {
            case let .tab(id):
                if let tab = tabManager.tab(withID: id) {
                    TabRowView(tab: tab, tabManager: tabManager, dropDestination: destination)
                        .padding(.leading, CGFloat(depth) * Self.indent)
                }
            case let .folder(folder):
                FolderRowView(folder: folder, tabManager: tabManager, dropDestination: destination)
                    .padding(.leading, CGFloat(depth) * Self.indent)
                if !folder.isCollapsed {
                    // AnyView : un type de vue ne peut pas se contenir lui-même directement.
                    AnyView(PinnedItemsView(items: folder.items, parent: folder.id, depth: depth + 1, tabManager: tabManager))
                }
            }
        }
    }
}
