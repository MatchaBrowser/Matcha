import SwiftUI

/// Hidden sidebar reduced to icons (Settings > Appearance, like Chrome's collapsed vertical tabs): favorites and today
/// tabs as their site icons (not the pinned tabs), “New Tab”, then the downloads button and the Spaces. The window's
/// buttons, the button that shows the sidebar again and the navigation are in the bar above (`CompactTopBar`); hovering
/// the column shows the whole sidebar over the page.
struct CompactSidebar: View {
    static let width = 48.0

    let model: WindowModel
    let tabManager: TabManager
    let newTab: () -> Void
    /// The downloads panel lives in the sidebar: it is shown first.
    let showDownloads: () -> Void

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        VStack(spacing: 6) {
            ScrollView {
                VStack(spacing: 4) {
                    // Two explicit sections: an icon keeps its identity when the favorites empty (review IU10).
                    let favorites = tabManager.favoriteTabs
                    let today = tabManager.todayTabs
                    ForEach(favorites) { tab in
                        CompactTabButton(tab: tab, tabManager: tabManager)
                    }
                    if !favorites.isEmpty, !today.isEmpty {
                        Divider()
                            .frame(width: 24)
                            .padding(.vertical, 2)
                    }
                    ForEach(today) { tab in
                        CompactTabButton(tab: tab, tabManager: tabManager)
                    }
                    Button("New Tab", systemImage: "plus", action: newTab)
                        .labelStyle(.iconOnly)
                        .buttonStyle(SidebarIconButtonStyle())
                        .help("New Tab")
                        .accessibilityIdentifier("compactNewTabButton")
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            DownloadsButton(model: model, downloads: downloads, action: showDownloads)
            if model.windowTabs == nil, model.session.spaces.count > 1 {
                spaces
            }
        }
        .frame(width: Self.width)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tabs"))
    }

    /// One icon per Space; a click shows it.
    private var spaces: some View {
        VStack(spacing: 2) {
            ForEach(model.session.spaces) { space in
                let isCurrent = space === model.space
                Button {
                    withMotion(.easeInOut(duration: 0.3)) { model.select(space) }
                } label: {
                    // The same as in the Space switcher: an emoji of another Space is dimmed there too.
                    SpaceIcon(space: space, isCurrent: isCurrent)
                }
                .buttonStyle(.plain)
                .help(space.record.name)
                .accessibilityLabel("Space \(space.record.name)")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .accessibilityIdentifier("compactSpaceButton")
            }
        }
    }
}

/// Icon of a tab in the column: its site icon, marked when the window shows it (the panes of a split too), the
/// speaker while it plays sound. A click shows it; hovering gives its title, a right click its menu.
private struct CompactTabButton: View {
    let tab: BrowserTab
    let tabManager: TabManager

    @State private var isHovered = false
    /// This window's selection; absent outside a browser window.
    @Environment(TabViewer.self) private var viewer: TabViewer?

    private var isSelected: Bool {
        (viewer ?? tabManager.activeViewer).displayedTabIDs.contains(tab.id)
    }

    var body: some View {
        FaviconView(tab: tab)
            // Unloaded pinned tab: present but dimmed, like its row.
            .opacity(tab.appearsLoaded ? 1 : 0.55)
            .frame(width: 32, height: 32)
            .background(SidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
            .overlay(alignment: .topTrailing) {
                if tab.isPlayingAudio {
                    PauseAudioButton(tab: tab, style: .badge)
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { TabActivation.activate(tab, in: tabManager) }
            .renamesOnDoubleClick(tab, tabManager: tabManager)
            .onHover { isHovered = $0 }
            .contextMenu { TabContextMenu(tab: tab, tabManager: tabManager) }
            .tabDraggable(tab)
            .help(tab.displayTitle)
            // Reached with ⇥ like a row of the sidebar (review IU18).
            .tabAccessibility(tab, tabManager: tabManager, isSelected: isSelected, canClose: true) { tabManager.moveStep(tab, by: $0) }
            .accessibilityIdentifier("compactTab")
    }
}
