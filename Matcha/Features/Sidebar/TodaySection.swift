import SwiftUI

/// Separator with “Clear”, “New Tab” button, then the today tabs.
struct TodaySection: View {
    let tabManager: TabManager
    let newTab: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(.separatorLine)
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
        // A split fits on one row, in place of its first tab.
        ForEach(tabManager.layout.todayRows) { row in
            switch row {
            case let .tab(id, index):
                if let tab = tabManager.tab(withID: id) {
                    TabRowView(tab: tab, tabManager: tabManager, dropDestination: .today(index: index))
                }
            case let .split(group, index):
                SplitRowView(group: group, tabManager: tabManager, dropDestination: .today(index: index))
            case .folder:
                EmptyView()
            }
        }
        // Large area below the today tabs, to drop them at the end of the list.
        SidebarDropZone(tabManager: tabManager, destination: .today(index: tabManager.layout.today.count), restingHeight: 60)
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

/// Icon at the width of a site icon, to align the text with the tabs' titles.
private struct NewTabLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: 16)
            configuration.title
        }
    }
}
