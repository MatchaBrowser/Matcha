import SwiftUI

/// Separator with “Clear”, above the today tabs of a Space.
struct TodayHeader: View {
    let tabManager: TabManager

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
    }
}
