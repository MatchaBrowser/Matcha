import SwiftUI

/// Icon of a tab: that of its site (`SiteIcon`), followed as it navigates.
struct FaviconView: View {
    let tab: BrowserTab
    var size = 16.0

    var body: some View {
        SiteIcon(favicon: tab.favicon, host: tab.displayedURL?.host(), size: size)
    }
}
