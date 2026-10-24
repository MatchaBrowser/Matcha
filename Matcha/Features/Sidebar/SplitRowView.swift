import SwiftUI

/// Row of a split: one segment per tab, from left to right like the panes. A click on a segment
/// displays the split with that pane active; the row is dragged as a whole; a tab or folder dropped
/// on it is inserted before the split, at `dropDestination`.
struct SplitRowView: View {
    /// Width of a segment from which it shows its tab's title.
    static let titleMinimumWidth = 64.0

    let group: SplitGroup
    let tabManager: TabManager
    let dropDestination: SidebarDestination

    @State private var isHovered = false
    @State private var isDropTargeted = false
    @State private var rowWidth = 0.0
    /// This window's selection; absent outside a browser window.
    @Environment(TabViewer.self) private var viewer: TabViewer?

    private var selectedTabID: BrowserTab.ID? {
        (viewer ?? tabManager.activeViewer).selectedTabID
    }

    private var tabs: [BrowserTab] {
        group.tabIDs.compactMap(tabManager.tab(withID:))
    }

    /// The split is displayed: the selected tab is part of it.
    private var isDisplayed: Bool {
        selectedTabID.map(group.contains) ?? false
    }

    /// ×, on hover: a today split, or a pinned split with a loaded tab.
    private var showsCloseButton: Bool {
        isHovered && (tabManager.layout.place(of: group.tabIDs[0]) == .today || tabManager.hasLoadedTab(inSplit: group.id))
    }

    private var titles: String {
        tabs.map(\.displayTitle).formatted(.list(type: .and))
    }

    var body: some View {
        let tabs = tabs
        let showsTitles = rowWidth / Double(max(tabs.count, 1)) >= Self.titleMinimumWidth
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    Rectangle()
                        .fill(.separatorLine)
                        .frame(width: 1, height: 16)
                }
                SplitSegmentView(
                    tab: tab,
                    tabManager: tabManager,
                    isActive: isDisplayed && selectedTabID == tab.id,
                    showsTitle: showsTitles,
                    isLast: index == tabs.count - 1,
                )
            }
        }
        .frame(height: 32)
        .background(SidebarRowBackground(isSelected: isDisplayed, isHovered: isHovered))
        // Over the last segment: nothing moves when it appears.
        .overlay(alignment: .trailing) {
            if showsCloseButton {
                Button("Close Split View", systemImage: "xmark") { tabManager.closeSplit(group.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(SidebarIconButtonStyle())
                    .scaleEffect(0.85)
                    .padding(.trailing, 3)
                    .accessibilityIdentifier("splitCloseButton")
            }
        }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { rowWidth = $0 }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .draggable(SidebarDragItem.split(group.id)) {
            SidebarDragPreview(title: titles) { Image(systemName: "rectangle.split.2x1") }
        }
        .sidebarDropDestination(tabManager: tabManager, destination: dropDestination, isTargeted: $isDropTargeted)
        .overlay(alignment: .top) {
            if isDropTargeted {
                InsertionLine()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(
            "Split View with \(titles)",
            comment: "Accessibility label of a split view row; %@ is the list of its tab titles",
        ))
        .accessibilityAction(named: Text("Close Split View")) { tabManager.closeSplit(group.id) }
        .accessibilityIdentifier("splitRow")
    }
}

/// Segment of a tab in a split's row: icon, title if there is room, and speaker while its page plays sound
/// (task 5.10).
private struct SplitSegmentView: View {
    /// Room for the row's ×, placed over the last segment on hover (with its 3 pt margin).
    static let closeButtonInset = SidebarIconButtonStyle.size + 3

    let tab: BrowserTab
    let tabManager: TabManager
    /// Active pane of the displayed split.
    let isActive: Bool
    let showsTitle: Bool
    /// Last segment, under the row's × on hover.
    let isLast: Bool

    var body: some View {
        HStack(spacing: 6) {
            FaviconView(tab: tab)
            if showsTitle {
                Text(tab.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Unloaded pinned tab: present but dimmed. A sleeping tab (task 5.6) does not change.
                    .foregroundStyle(tab.appearsLoaded ? .primary : .secondary)
            }
            if tab.isPlayingAudio {
                if showsTitle {
                    Spacer(minLength: 0)
                }
                PauseAudioButton(tab: tab, style: .segment)
            }
        }
        .padding(.leading, 6)
        // Last segment playing sound: the speaker stays left of the ×, without moving when it appears.
        .padding(.trailing, isLast && tab.isPlayingAudio ? Self.closeButtonInset : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsTitle ? .leading : .center)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.subtleFill)
                    .padding(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { TabActivation.activate(tab, in: tabManager) }
        .contextMenu { TabContextMenu(tab: tab, tabManager: tabManager) }
        .help(tab.url?.absoluteString ?? tab.displayTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tab.displayTitle))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { TabActivation.activate(tab, in: tabManager) }
        .accessibilityIdentifier("splitSegment")
        .tabAudioAccessibility(tab)
    }
}
