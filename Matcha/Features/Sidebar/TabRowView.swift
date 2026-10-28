import AppKit
import SwiftUI

/// Row of a pinned or today tab: icon, title, speaker while the page plays sound (task 5.10), close button on
/// hover. It can be dragged; an item dropped on its top half is inserted before it, on its bottom half after it
/// (`drop`). A pinned tab's name is edited in the row, like a folder's (`TabManager+Names`).
struct TabRowView: View {
    let tab: BrowserTab
    let tabManager: TabManager
    let drop: SidebarRowDrop

    @State private var isHovered = false
    @State private var dropPart: SidebarRowDrop.Part?
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool
    /// This window's selection; absent outside a browser window.
    @Environment(TabViewer.self) private var viewer: TabViewer?

    private var isSelected: Bool {
        (viewer ?? tabManager.activeViewer).selectedTabID == tab.id
    }

    private var isRenaming: Bool {
        tabManager.renamingTabID == tab.id
    }

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab)
            if isRenaming {
                nameField
            } else {
                Text(tab.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Unloaded pinned tab: present but dimmed. A sleeping tab (task 5.6) does not change.
                    .foregroundStyle(tab.appearsLoaded ? .primary : .secondary)
            }
            Spacer(minLength: 0)
            if tab.isPlayingAudio {
                HStack(spacing: 0) {
                    PauseAudioButton(tab: tab)
                    if isHovered {
                        closeButton
                    } else {
                        // Room for the ×: the speaker does not move when it appears, a click does not close the tab.
                        Color.clear.frame(width: SidebarIconButtonStyle.size)
                    }
                }
            } else if isHovered, tab.appearsLoaded {
                closeButton
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(height: 32)
        .background(SidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else {
                return
            }
            TabActivation.activate(tab, in: tabManager)
        }
        .renamesOnDoubleClick(tab, tabManager: tabManager, inRow: true)
        .onHover { isHovered = $0 }
        .contextMenu { TabContextMenu(tab: tab, tabManager: tabManager, renamesInRow: true) }
        .tabDraggable(tab)
        .sidebarRowDropDestination(tabManager: tabManager, drop: drop, part: $dropPart)
        .insertionLine(for: dropPart)
        .help(tab.displayedURL?.absoluteString ?? tab.displayTitle)
        .tabAccessibility(tab, tabManager: tabManager, isSelected: isSelected, canClose: true, isEditing: isRenaming) {
            tabManager.moveStep(tab, by: $0)
        }
        .accessibilityIdentifier("tabRow")
    }

    /// Starts with the title shown, selected; the page's title shows when it is emptied, which gives it back.
    private var nameField: some View {
        TextField("Tab name", text: $draftName, prompt: Text(verbatim: tab.pageTitle))
            .textFieldStyle(.plain)
            .focused($isNameFocused)
            .onSubmit { tabManager.renameTab(tab, to: draftName) }
            .onExitCommand { tabManager.endRenaming(tab) }
            .onChange(of: isNameFocused) { _, focused in
                // Clicking elsewhere confirms the typed name.
                if !focused, isRenaming {
                    tabManager.renameTab(tab, to: draftName)
                }
            }
            .onAppear { draftName = tab.displayTitle }
            // The row went away (tab closed or moved): its editing ends.
            .onDisappear { tabManager.endRenaming(tab) }
            .task {
                await FolderNameSelection.run(
                    focus: { isNameFocused = true },
                    isFocused: { isNameFocused },
                    selectAll: { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) },
                )
            }
            .accessibilityIdentifier("tabNameField")
    }

    private var closeButton: some View {
        Button("Close Tab", systemImage: "xmark") { tabManager.close(tab) }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .scaleEffect(0.85)
    }
}
