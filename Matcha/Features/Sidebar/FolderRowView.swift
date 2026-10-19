import AppKit
import SwiftUI

/// Row of a pinned folder: a click collapses or expands it; a menu to rename it, customize it (icon, text and
/// background colors, `FolderCustomizationPanel`), create a subfolder in it or delete it. An item dropped on the
/// row goes into the folder, or is placed before it if it is released on the top of the row.
struct FolderRowView: View {
    /// Height of the top of the row where a drop places the item before the folder.
    static let beforeZoneHeight = 8.0

    let folder: PinnedFolder
    let tabManager: TabManager
    /// Position of the folder in its parent.
    let dropDestination: SidebarDestination

    @Environment(WindowModel.self) private var windowModel: WindowModel?
    @State private var isHovered = false
    @State private var isDropTargeted = false
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var isRenaming: Bool {
        tabManager.renamingFolderID == folder.id
    }

    /// Color of the name and the symbol: chosen, or readable on the chosen background; nil: the system's color.
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
            withMotion(.easeOut(duration: 0.15)) { tabManager.toggleFolder(folder.id) }
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
        .sidebarRowKeyboard(isEnabled: !isRenaming) {
            withMotion(.easeOut(duration: 0.15)) { tabManager.toggleFolder(folder.id) }
        } move: { tabManager.moveFolderStep(folder.id, by: $0) }
        .accessibilityIdentifier("folderRow")
    }

    /// System gray; on a chosen background, where this gray may vanish, the dimmed text color.
    private var chevronStyle: AnyShapeStyle {
        guard folder.appearance.backgroundColor != nil else {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle((textColor ?? .primary).opacity(0.7))
    }

    /// In Debug, the chosen appearance (“symbol:star text:#FF3B30 background:none”), for the UI tests.
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
                // Clicking elsewhere confirms the typed name.
                if !focused, isRenaming {
                    tabManager.renameFolder(folder.id, to: draftName)
                }
            }
            .onAppear { draftName = folder.name }
            .task {
                // The field often appears while a context menu is closing: wait for it
                // to finish before taking the keyboard, then select the name.
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
            // The same item closes the panel open below this folder.
            if windowModel.customizedFolderID == folder.id {
                Button("Close Customization") { toggleCustomization(in: windowModel) }
            } else {
                Button("Customize…") { toggleCustomization(in: windowModel) }
            }
        }
        Button("New Subfolder") { tabManager.newFolder(in: folder.id) }
        Divider()
        Button("Delete Folder") {
            withMotion(.easeOut(duration: 0.15)) {
                if windowModel?.customizedFolderID == folder.id {
                    windowModel?.customizedFolderID = nil
                }
                tabManager.deleteFolder(folder.id)
            }
        }
    }

    private func toggleCustomization(in windowModel: WindowModel) {
        withMotion(.easeOut(duration: 0.2)) { windowModel.toggleFolderCustomization(folder.id) }
    }
}

/// Background of a folder's row: the chosen color, solid, lightened or darkened on hover (towards the text color
/// readable on it); without a color, that of the other rows.
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
