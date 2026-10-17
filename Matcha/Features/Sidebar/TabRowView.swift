import SwiftUI

/// Ligne d'un onglet épinglé ou du jour : icône, titre, bouton de fermeture au survol.
/// On peut la faire glisser ; un onglet déposé dessus s'insère avant elle, à `dropDestination`.
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
                // Onglet épinglé déchargé : présent mais en retrait.
                .foregroundStyle(tab.isLoaded ? .primary : .secondary)
            Spacer(minLength: 0)
            if isHovered, tab.isLoaded {
                Button("Close Tab", systemImage: "xmark") { tabManager.close(tab) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(SidebarIconButtonStyle())
                    .scaleEffect(0.85)
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
        .accessibilityIdentifier("tabRow")
    }
}

/// Fond d'une ligne ou d'une tuile : marqué pour l'onglet sélectionné, léger au survol.
struct SidebarRowBackground: View {
    let isSelected: Bool
    let isHovered: Bool
    var cornerRadius = 8.0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fill)
            .shadow(color: .black.opacity(isSelected && colorScheme == .light ? 0.08 : 0), radius: 1, y: 1)
    }

    private var fill: Color {
        if isSelected {
            return colorScheme == .dark ? .white.opacity(0.16) : .white.opacity(0.8)
        }
        return isHovered ? Color.primary.opacity(0.07) : .clear
    }
}
