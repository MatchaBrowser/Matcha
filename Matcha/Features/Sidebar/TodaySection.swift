import SwiftUI

/// Séparateur avec « Effacer », bouton « Nouvel onglet », puis les onglets du jour.
struct TodaySection: View {
    let tabManager: TabManager
    let newTab: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
            if !tabManager.todayTabs.isEmpty {
                Button(action: tabManager.clearToday) {
                    Text("Clear", comment: "Sidebar button that closes all Today tabs.")
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .help("Close all Today tabs")
            }
        }
        .frame(height: 24)
        NewTabRow(action: newTab)
        let today = tabManager.todayTabs
        ForEach(Array(today.enumerated()), id: \.element.id) { index, tab in
            TabRowView(tab: tab, tabManager: tabManager, dropDestination: .today(index: index))
        }
        // Grande zone sous les onglets du jour, pour les déposer en fin de liste.
        SidebarDropZone(tabManager: tabManager, destination: .today(index: today.count), restingHeight: 60)
            .accessibilityIdentifier("todayDropZone")
    }
}

private struct NewTabRow: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label("New Tab", systemImage: "plus")
                .labelStyle(NewTabLabelStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(SidebarRowBackground(isSelected: false, isHovered: isHovered))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("newTabButton")
    }
}

/// Icône à la largeur d'une icône de site, pour aligner le texte sur les titres des onglets.
private struct NewTabLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: 16)
            configuration.title
        }
    }
}
