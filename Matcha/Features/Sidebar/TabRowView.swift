import SwiftUI

/// Row of a pinned or today tab: icon, title, speaker while the page plays sound (task 5.10), close button on
/// hover. It can be dragged; an item dropped on its top half is inserted before it, on its bottom half after it
/// (`drop`).
struct TabRowView: View {
    let tab: BrowserTab
    let tabManager: TabManager
    let drop: SidebarRowDrop

    @State private var isHovered = false
    @State private var dropPart: SidebarRowDrop.Part?
    /// This window's selection; absent outside a browser window.
    @Environment(TabViewer.self) private var viewer: TabViewer?

    private var isSelected: Bool {
        (viewer ?? tabManager.activeViewer).selectedTabID == tab.id
    }

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab)
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                // Unloaded pinned tab: present but dimmed. A sleeping tab (task 5.6) does not change.
                .foregroundStyle(tab.appearsLoaded ? .primary : .secondary)
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
        .onTapGesture { TabActivation.activate(tab, in: tabManager) }
        .onHover { isHovered = $0 }
        .contextMenu { TabContextMenu(tab: tab, tabManager: tabManager) }
        .tabDraggable(tab)
        .sidebarRowDropDestination(tabManager: tabManager, drop: drop, part: $dropPart)
        .insertionLine(for: dropPart)
        .help(tab.url?.absoluteString ?? tab.displayTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { TabActivation.activate(tab, in: tabManager) }
        .accessibilityAction(named: "Close Tab") { tabManager.close(tab) }
        .sidebarRowKeyboard { TabActivation.activate(tab, in: tabManager) } move: { tabManager.moveStep(tab, by: $0) }
        .accessibilityIdentifier("tabRow")
        // “Playing Audio”; in Debug, “suspended” for a sleeping tab (UI tests of task 5.6).
        .tabAudioAccessibility(tab)
    }

    private var closeButton: some View {
        Button("Close Tab", systemImage: "xmark") { tabManager.close(tab) }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .scaleEffect(0.85)
    }
}
