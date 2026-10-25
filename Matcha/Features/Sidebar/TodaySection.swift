import SwiftUI

/// Header (separator with “Clear”, or “This Window” in a window of its own tabs), “New Tab” button, then the today
/// tabs.
struct TodaySection<Header: View>: View {
    let tabManager: TabManager
    let newTab: () -> Void
    @ViewBuilder let header: () -> Header

    var body: some View {
        header()
        NewTabRow(action: newTab)
        // A split fits on one row, in place of its first tab.
        ForEach(tabManager.layout.todayRows) { row in
            switch row {
            case let .tab(id, _):
                if let tab = tabManager.tab(withID: id) {
                    TabRowView(tab: tab, tabManager: tabManager, drop: .today(row))
                }
            case let .split(group, _):
                SplitRowView(group: group, tabManager: tabManager, drop: .today(row))
            case .folder:
                EmptyView()
            }
        }
        // Large area below the today tabs, to drop them at the end of the list.
        SidebarDropZone(tabManager: tabManager, destination: .today(index: tabManager.layout.today.count), restingHeight: 60)
            .accessibilityIdentifier("todayDropZone")
    }
}

extension TodaySection where Header == TodayHeader {
    init(tabManager: TabManager, newTab: @escaping () -> Void) {
        self.init(tabManager: tabManager, newTab: newTab) { TodayHeader(tabManager: tabManager) }
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
