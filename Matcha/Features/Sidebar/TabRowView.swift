import SwiftUI

/// Row of a pinned or today tab: icon, title, speaker while the page plays sound (task 5.10), close button on
/// hover. It can be dragged; a tab dropped on it is inserted before it, at `dropDestination`.
struct TabRowView: View {
    let tab: BrowserTab
    let tabManager: TabManager
    let dropDestination: SidebarDestination

    @State private var isHovered = false
    @State private var isDropTargeted = false

    private var isSelected: Bool {
        tabManager.selectedTabID == tab.id
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
        .sidebarDropDestination(tabManager: tabManager, destination: dropDestination, isTargeted: $isDropTargeted)
        .overlay(alignment: .top) {
            if isDropTargeted {
                InsertionLine()
            }
        }
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

/// Background of a row or a tile: marked for the selected tab, light on hover.
struct SidebarRowBackground: View {
    let isSelected: Bool
    let isHovered: Bool
    var cornerRadius = 8.0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fill)
            .shadow(color: .black.opacity(isSelected && colorScheme == .light ? 0.08 : 0), radius: 1, y: 1)
            .overlay {
                // “Increase contrast” (audit H3): the selected row is outlined, not only lighter.
                if isSelected, contrast == .increased {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                }
            }
    }

    private var fill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.8))
        }
        return isHovered ? AnyShapeStyle(.subtleFill) : AnyShapeStyle(Color.clear)
    }
}
