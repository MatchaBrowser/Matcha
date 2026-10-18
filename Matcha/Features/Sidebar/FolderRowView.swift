import AppKit
import SwiftUI

/// Ligne d'un dossier d'épinglés : un clic le replie ou le déplie ; menu pour le renommer, le personnaliser (icône,
/// couleurs du texte et du fond, `FolderCustomizationPanel`), y créer un sous-dossier ou le supprimer. Un élément
/// déposé sur la ligne entre dans le dossier, ou se place avant lui s'il est lâché sur le haut de la ligne.
struct FolderRowView: View {
    /// Hauteur du haut de la ligne où un dépôt place l'élément avant le dossier.
    static let beforeZoneHeight = 8.0

    let folder: PinnedFolder
    let tabManager: TabManager
    /// Place du dossier dans son parent.
    let dropDestination: SidebarDestination

    @Environment(WindowModel.self) private var windowModel: WindowModel?
    @State private var isHovered = false
    @State private var isDropTargeted = false
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var isRenaming: Bool {
        tabManager.renamingFolderID == folder.id
    }

    /// Couleur du nom et du symbole : choisie, ou lisible sur le fond choisi ; nil : celle du système.
    private var textColor: Color? {
        folder.appearance.displayedTextColor?.color
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(folder.isCollapsed ? 0 : 90))
                .foregroundStyle(chevronStyle)
                .frame(width: 10)
            SidebarIconView(icon: folder.appearance.icon, defaultSymbol: SidebarIcon.defaultFolderSymbol, tint: textColor)
                .frame(width: 16)
            if isRenaming {
                nameField
            } else {
                Text(folder.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(textColor ?? .primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(FolderRowBackground(appearance: folder.appearance, isHovered: isHovered || isDropTargeted))
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
            SidebarDragPreview(title: folder.name) {
                SidebarIconView(icon: folder.appearance.icon, defaultSymbol: SidebarIcon.defaultFolderSymbol)
            }
        }
        .sidebarDropDestination(tabManager: tabManager, isTargeted: $isDropTargeted) { location in
            location.y < Self.beforeZoneHeight ? dropDestination : .pinned(folder: folder.id, index: folder.items.count)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(folder.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("folderRow")
    }

    /// Gris du système ; sur un fond choisi, où ce gris peut disparaître, la couleur du texte atténuée.
    private var chevronStyle: AnyShapeStyle {
        guard folder.appearance.backgroundColor != nil else {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle((textColor ?? .primary).opacity(0.7))
    }

    /// En Debug, l'apparence choisie (« symbol:star text:#FF3B30 background:none »), pour les tests d'interface.
    private var accessibilityValue: Text {
        #if DEBUG
            return Text(verbatim: folder.appearance.summary)
        #else
            return Text(verbatim: "")
        #endif
    }

    private var nameField: some View {
        TextField("Folder name", text: $draftName)
            .textFieldStyle(.plain)
            .foregroundStyle(textColor ?? .primary)
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
        if let windowModel {
            // Le même élément ferme le panneau ouvert sous ce dossier.
            if windowModel.customizedFolderID == folder.id {
                Button("Close Customization") { toggleCustomization(in: windowModel) }
            } else {
                Button("Customize…") { toggleCustomization(in: windowModel) }
            }
        }
        Button("New Subfolder") { tabManager.newFolder(in: folder.id) }
        Divider()
        Button("Delete Folder") {
            withAnimation(.easeOut(duration: 0.15)) {
                if windowModel?.customizedFolderID == folder.id {
                    windowModel?.customizedFolderID = nil
                }
                tabManager.deleteFolder(folder.id)
            }
        }
    }

    private func toggleCustomization(in windowModel: WindowModel) {
        withAnimation(.easeOut(duration: 0.2)) { windowModel.toggleFolderCustomization(folder.id) }
    }
}

/// Fond de la ligne d'un dossier : la couleur choisie, pleine, éclaircie ou assombrie au survol (dans la couleur du
/// texte lisible sur elle) ; sans couleur, celui des autres lignes.
private struct FolderRowBackground: View {
    let appearance: FolderAppearance
    let isHovered: Bool

    var body: some View {
        if let fill = appearance.backgroundColor {
            RoundedRectangle(cornerRadius: 8)
                .fill(fill.color)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fill.readableTextColor.color.opacity(isHovered ? 0.15 : 0))
                }
        } else {
            SidebarRowBackground(isSelected: false, isHovered: isHovered)
        }
    }
}
