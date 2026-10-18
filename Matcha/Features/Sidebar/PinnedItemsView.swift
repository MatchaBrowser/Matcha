import SwiftUI

/// Contenu d'un niveau des épinglés : onglets, splits (une ligne chacun) et dossiers, avec le contenu des
/// dossiers dépliés, indenté d'un cran par niveau. Sous la ligne d'un dossier, son panneau de personnalisation s'il
/// est ouvert dans la fenêtre (toute la largeur de la barre, sans retrait).
struct PinnedItemsView: View {
    static let indent = 14.0

    let items: [PinnedItem]
    /// Dossier qui contient ces éléments, nil pour la racine des épinglés.
    let parent: UUID?
    let depth: Int
    let tabManager: TabManager

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    var body: some View {
        ForEach(tabManager.layout.pinnedRows(items)) { row in
            let destination = SidebarDestination.pinned(folder: parent, index: row.index)
            switch row {
            case let .tab(id, _):
                if let tab = tabManager.tab(withID: id) {
                    TabRowView(tab: tab, tabManager: tabManager, dropDestination: destination)
                        .padding(.leading, CGFloat(depth) * Self.indent)
                }
            case let .split(group, _):
                SplitRowView(group: group, tabManager: tabManager, dropDestination: destination)
                    .padding(.leading, CGFloat(depth) * Self.indent)
            case let .folder(folder, _):
                FolderRowView(folder: folder, tabManager: tabManager, dropDestination: destination)
                    .padding(.leading, CGFloat(depth) * Self.indent)
                if let windowModel, windowModel.customizedFolderID == folder.id {
                    FolderCustomizationPanel(folder: folder, tabManager: tabManager) {
                        withAnimation(.easeOut(duration: 0.2)) { windowModel.customizedFolderID = nil }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !folder.isCollapsed {
                    // AnyView : un type de vue ne peut pas se contenir lui-même directement.
                    AnyView(PinnedItemsView(items: folder.items, parent: folder.id, depth: depth + 1, tabManager: tabManager))
                }
            }
        }
    }
}
