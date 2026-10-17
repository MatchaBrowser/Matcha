import SwiftUI

/// Icône d'un onglet : celle de son site (`SiteIcon`), suivie au fil de la navigation.
struct FaviconView: View {
    let tab: BrowserTab
    var size = 16.0

    var body: some View {
        SiteIcon(favicon: tab.favicon, host: tab.url?.host(), size: size)
    }
}
