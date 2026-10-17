import SwiftUI

/// Zone de dépôt en fin de section : fine au repos, elle s'agrandit quand on y amène un élément.
/// Dans une section vide, elle affiche le nom de la section.
struct SidebarDropZone: View {
    let tabManager: TabManager
    let destination: SidebarDestination
    /// Nom de la section, affiché quand elle est vide.
    var label: LocalizedStringResource?
    var restingHeight = 8.0

    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(Color.primary.opacity(isTargeted ? 0.35 : 0))
            .overlay {
                if isTargeted, let label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: isTargeted ? 36 : restingHeight)
            .contentShape(Rectangle())
            .sidebarDropDestination(tabManager: tabManager, isTargeted: $isTargeted) { _ in destination }
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
    }

    /// « Déposer dans Favoris » dans une section vide, « Déposer ici » sinon.
    private var accessibilityLabel: Text {
        if let label {
            Text(
                "Drop into \(Text(label))",
                comment: "Accessibility label of an empty sidebar section drop zone; %@ is the section name (Favorites, Pinned).",
            )
        } else {
            Text("Drop here", comment: "Accessibility label of the drop zone at the end of a sidebar section.")
        }
    }
}

extension View {
    /// Accepte un onglet, un split ou un dossier glissé et le range à la destination calculée d'après
    /// l'endroit du dépôt dans la vue. Un dossier n'est accepté que parmi les épinglés, un split hors des favoris.
    func sidebarDropDestination(
        tabManager: TabManager,
        isTargeted: Binding<Bool>,
        destination: @escaping (CGPoint) -> SidebarDestination,
    ) -> some View {
        dropDestination(for: SidebarDragItem.self) { items, location in
            guard let item = items.first else {
                return false
            }
            let target = destination(location)
            switch item {
            case let .tab(id):
                guard let tab = tabManager.tab(withID: id) else {
                    return false
                }
                withAnimation(.easeOut(duration: 0.15)) { tabManager.move(tab, to: target) }
            case let .folder(id):
                guard case .pinned = target else {
                    return false
                }
                withAnimation(.easeOut(duration: 0.15)) { tabManager.moveFolder(id, to: target) }
            case let .split(id):
                if case .favorites = target {
                    return false
                }
                guard tabManager.layout.split(withID: id) != nil else {
                    return false
                }
                withAnimation(.easeOut(duration: 0.15)) { tabManager.moveSplit(id, to: target) }
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.1)) { isTargeted.wrappedValue = targeted }
        }
    }

    /// Accepte un élément glissé et le range à `destination`.
    func sidebarDropDestination(tabManager: TabManager, destination: SidebarDestination, isTargeted: Binding<Bool>) -> some View {
        sidebarDropDestination(tabManager: tabManager, isTargeted: isTargeted) { _ in destination }
    }

    /// Rend l'onglet déplaçable, avec un aperçu compact.
    func tabDraggable(_ tab: BrowserTab) -> some View {
        draggable(SidebarDragItem.tab(tab.id)) {
            SidebarDragPreview(title: tab.displayTitle) { FaviconView(tab: tab) }
        }
    }
}

/// Aperçu affiché sous le pointeur pendant un glisser.
struct SidebarDragPreview<Icon: View>: View {
    let title: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 8) {
            icon()
            Text(title)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
    }
}

/// Trait qui marque l'endroit où l'élément glissé sera inséré.
struct InsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .offset(y: -1)
    }
}
