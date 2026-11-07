import SwiftUI

/// Icon of a tab: that of its site (`SiteIcon`), followed as it navigates.
struct FaviconView: View {
    let tab: BrowserTab
    var size = 16.0

    var body: some View {
        if tab.noteID != nil {
            // A note in a tab (task 12.5).
            Image(systemName: "doc.text")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else {
            SiteIcon(favicon: tab.favicon, host: tab.displayedURL?.host(), size: size)
        }
    }
}
