import SwiftUI

/// Drop zone at the end of a section: thin at rest, it grows when an item is brought over it.
/// In an empty section, it shows the section's name.
struct SidebarDropZone: View {
    let tabManager: TabManager
    let destination: SidebarDestination
    /// Name of the section, displayed when it is empty.
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

    /// “Drop into Favorites” in an empty section, “Drop here” otherwise.
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
    /// Accepts a dragged tab, split or folder and puts it at the destination computed from where it was dropped in the
    /// view (`SidebarDropModifier`).
    func sidebarDropDestination(
        tabManager: TabManager,
        isTargeted: Binding<Bool>,
        destination: @escaping (CGPoint) -> SidebarDestination,
    ) -> some View {
        modifier(SidebarDropModifier(tabManager: tabManager, isTargeted: isTargeted, destination: destination))
    }

    /// Accepts a dragged item and puts it at `destination`.
    func sidebarDropDestination(tabManager: TabManager, destination: SidebarDestination, isTargeted: Binding<Bool>) -> some View {
        sidebarDropDestination(tabManager: tabManager, isTargeted: isTargeted) { _ in destination }
    }

    /// Makes the tab draggable, with a compact preview; dropped outside the app's windows, it opens in a new window.
    func tabDraggable(_ tab: BrowserTab) -> some View {
        draggable(SidebarDragItem.tab(tab.id)) {
            SidebarDragPreview(title: tab.displayTitle) { FaviconView(tab: tab) }
        }
        .modifier(TabDragOutModifier(tab: tab))
    }
}

/// Preview displayed under the pointer during a drag.
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

/// Line marking where the dragged item will be inserted.
struct InsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .offset(y: -1)
    }
}
