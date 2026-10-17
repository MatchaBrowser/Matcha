import AppKit
import SwiftUI

/// Ligne d'un dossier d'épinglés : un clic le replie ou le déplie ; menu pour le renommer, y créer un
/// sous-dossier ou le supprimer. Un élément déposé sur la ligne entre dans le dossier, ou se place
/// avant lui s'il est lâché sur le haut de la ligne.
struct FolderRowView: View {
    /// Hauteur du haut de la ligne où un dépôt place l'élément avant le dossier.
    static let beforeZoneHeight = 8.0

    let folder: PinnedFolder
    let tabManager: TabManager
    /// Place du dossier dans son parent.
    let dropDestination: SidebarDestination

    @State private var isHovered = false
    @State private var isDropTargeted = false
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var isRenaming: Bool {
        tabManager.renamingFolderID == folder.id
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(folder.isCollapsed ? 0 : 90))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            Image(systemName: "folder")
                .font(.system(size: 13))
                .frame(width: 16)
            if isRenaming {
                nameField
            } else {
                Text(folder.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(SidebarRowBackground(isSelected: false, isHovered: isHovered || isDropTargeted))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else {
                return
            }
            withAnimation(.easeOut(duration: 0.15)) { tabManager.toggleFolder(folder.id) }
        }
        .onHover { isHovered = $0 }
        .contextMenu { menu }
        .draggable(SidebarDragItem.folder(folder.id)) {
            SidebarDragPreview(title: folder.name) { Image(systemName: "folder") }
        }
        .sidebarDropDestination(tabManager: tabManager, isTargeted: $isDropTargeted) { location in
            location.y < Self.beforeZoneHeight ? dropDestination : .pinned(folder: folder.id, index: folder.items.count)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(folder.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("folderRow")
    }

    private var nameField: some View {
        TextField("Folder name", text: $draftName)
            .textFieldStyle(.plain)
            .focused($isNameFocused)
            .onSubmit { tabManager.renameFolder(folder.id, to: draftName) }
            .onExitCommand { tabManager.renameFolder(folder.id, to: folder.name) }
            .onChange(of: isNameFocused) { _, focused in
                // Cliquer ailleurs valide le nom saisi.
                if !focused, isRenaming {
                    tabManager.renameFolder(folder.id, to: draftName)
                }
            }
            .onAppear { draftName = folder.name }
            .task {
                // Le champ apparaît souvent pendant la fermeture d'un menu contextuel : on attend
                // qu'elle soit finie pour prendre le clavier, puis on sélectionne le nom.
                try? await Task.sleep(for: .milliseconds(80))
                isNameFocused = true
                try? await Task.sleep(for: .milliseconds(20))
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .accessibilityIdentifier("folderNameField")
    }

    @ViewBuilder private var menu: some View {
        Button("Rename") { tabManager.renamingFolderID = folder.id }
        Button("New Subfolder") { tabManager.newFolder(in: folder.id) }
        Divider()
        Button("Delete Folder") {
            withAnimation(.easeOut(duration: 0.15)) { tabManager.deleteFolder(folder.id) }
        }
    }
}
