import SwiftUI

/// Title of a browser window (Window menu, Mission Control, VoiceOver): the selected tab's, “Private Browsing” in a
/// private window. A view of its own, so that only it follows the page titles (audit H4).
struct WindowTitle: View {
    let session: BrowserSession
    let tabManager: TabManager
    let viewer: TabViewer

    var body: some View {
        Color.clear
            .navigationTitle(session.isPrivate ? String(localized: "Private Browsing") : tabManager.selectedTab(in: viewer)?
                .displayTitle ?? "Matcha")
            .accessibilityHidden(true)
    }
}
