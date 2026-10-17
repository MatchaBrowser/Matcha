import SwiftUI

/// Ligne d'un split : un morceau par onglet, de gauche à droite comme les panneaux. Un clic sur un morceau
/// affiche le split avec ce panneau actif ; la ligne se glisse en entier ; un onglet ou un dossier déposé
/// dessus s'insère avant le split, à `dropDestination`.
struct SplitRowView: View {
    /// Largeur d'un morceau à partir de laquelle il montre le titre de son onglet.
    static let titleMinimumWidth = 64.0

    let group: SplitGroup
    let tabManager: TabManager
    let dropDestination: SidebarDestination

    @State private var isHovered = false
    @State private var isDropTargeted = false
    @State private var rowWidth = 0.0

    private var tabs: [BrowserTab] {
        group.tabIDs.compactMap(tabManager.tab(withID:))
    }

    /// Le split est affiché : l'onglet sélectionné en fait partie.
    private var isDisplayed: Bool {
        tabManager.selectedTabID.map(group.contains) ?? false
    }

    /// ×, au survol : split du jour, ou split épinglé dont un onglet est chargé.
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
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 1, height: 16)
                }
                SplitSegmentView(
                    tab: tab,
                    tabManager: tabManager,
                    isActive: isDisplayed && tabManager.selectedTabID == tab.id,
                    showsTitle: showsTitles,
                )
            }
        }
        .frame(height: 32)
        .background(SidebarRowBackground(isSelected: isDisplayed, isHovered: isHovered))
        // Par-dessus le dernier morceau : rien ne bouge quand il apparaît.
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

/// Morceau d'un onglet dans la ligne d'un split : icône, et titre si la place le permet.
private struct SplitSegmentView: View {
    let tab: BrowserTab
    let tabManager: TabManager
    /// Panneau actif du split affiché.
    let isActive: Bool
    let showsTitle: Bool

    var body: some View {
        HStack(spacing: 6) {
            FaviconView(tab: tab)
            if showsTitle {
                Text(tab.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Onglet épinglé déchargé : présent mais en retrait.
                    .foregroundStyle(tab.isLoaded ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsTitle ? .leading : .center)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
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
    }
}
