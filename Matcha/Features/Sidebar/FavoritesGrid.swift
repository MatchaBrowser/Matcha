import SwiftUI

/// Favorites: a grid of icon tiles, four per row, followed by a drop zone.
struct FavoritesGrid: View {
    let tabManager: TabManager

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        let favorites = tabManager.favoriteTabs
        VStack(spacing: 0) {
            if !favorites.isEmpty {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(favorites.enumerated()), id: \.element.id) { index, tab in
                        FavoriteTile(tab: tab, tabManager: tabManager, dropDestination: .favorites(index: index))
                    }
                }
            }
            SidebarDropZone(
                tabManager: tabManager,
                destination: .favorites(index: favorites.count),
                label: favorites.isEmpty ? "Favorites" : nil,
                restingHeight: favorites.isEmpty ? 6 : 4,
            )
            .accessibilityIdentifier("favoritesDropZone")
        }
    }
}

/// Tile of a favorite, with a speaker badge while its page plays sound (task 5.10); a tab dropped on it is inserted
/// before it.
private struct FavoriteTile: View {
    let tab: BrowserTab
    let tabManager: TabManager
    let dropDestination: SidebarDestination

    @State private var isHovered = false
    @State private var isDropTargeted = false

    private var isSelected: Bool {
        tabManager.selectedTabID == tab.id
    }

    var body: some View {
        FaviconView(tab: tab, size: 20)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
                    SidebarRowBackground(isSelected: isSelected, isHovered: isHovered, cornerRadius: 10)
                },
            )
            .overlay(alignment: .leading) {
                if isDropTargeted {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: -4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if tab.isPlayingAudio {
                    PauseAudioButton(tab: tab, style: .badge)
                        .padding(3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { TabActivation.activate(tab, in: tabManager) }
            .onHover { isHovered = $0 }
            .contextMenu { TabContextMenu(tab: tab, tabManager: tabManager) }
            .tabDraggable(tab)
            .sidebarDropDestination(tabManager: tabManager, destination: dropDestination, isTargeted: $isDropTargeted)
            .help(tab.displayTitle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.displayTitle)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { TabActivation.activate(tab, in: tabManager) }
            .sidebarRowKeyboard(isHorizontal: true) { TabActivation.activate(tab, in: tabManager) } move: {
                tabManager.moveStep(tab, by: $0)
            }
            .accessibilityIdentifier("favoriteTile")
            .tabAudioAccessibility(tab)
    }
}
