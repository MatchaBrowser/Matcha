import SwiftUI

/// “Split view” items of a tab's context menu: open it next to the active pane (dimmed when the displayed split
/// is full, absent when impossible), remove it from its split, or undo the split.
struct SplitMenuItems: View {
    let tab: BrowserTab
    let tabManager: TabManager

    var body: some View {
        let availability = tabManager.splitAvailability(for: tab.id)
        let group = tabManager.split(containing: tab)
        if availability != .unavailable {
            Button("Open in Split View") {
                if tabManager.openInSplit(tab) {
                    TabActivation.activate(tab, in: tabManager)
                }
            }
            .disabled(availability == .full)
        }
        if let group {
            Button("Remove from Split View") { tabManager.removeFromSplit(tab) }
            Button("Separate Tabs") { tabManager.separateSplit(group.id) }
        }
        if availability != .unavailable || group != nil {
            Divider()
        }
    }
}
