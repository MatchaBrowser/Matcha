import SwiftUI

/// Ligne d'un onglet épinglé ou du jour : icône, titre, haut-parleur pendant que la page joue du son (tâche 5.10),
/// bouton de fermeture au survol. On peut la faire glisser ; un onglet déposé dessus s'insère avant elle, à
/// `dropDestination`.
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
                // Onglet épinglé déchargé : présent mais en retrait. Un onglet en veille (tâche 5.6) ne change pas.
                .foregroundStyle(tab.appearsLoaded ? .primary : .secondary)
            Spacer(minLength: 0)
            if tab.isPlayingAudio {
                HStack(spacing: 0) {
                    PauseAudioButton(tab: tab)
                    if isHovered {
                        closeButton
                    } else {
                        // Place du × : le haut-parleur ne bouge pas quand il apparaît, un clic ne ferme pas l'onglet.
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
        .accessibilityIdentifier("tabRow")
        // « Lecture audio » ; en Debug, « suspended » pour un onglet en veille (tests d'interface de la tâche 5.6).
        .tabAudioAccessibility(tab)
    }

    private var closeButton: some View {
        Button("Close Tab", systemImage: "xmark") { tabManager.close(tab) }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .scaleEffect(0.85)
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
