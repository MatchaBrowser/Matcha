import SwiftUI

/// Icon of a site with no open tab (typed address, history): the one already cached for its domain, otherwise the
/// initial. Downloads nothing.
struct CachedSiteIcon: View {
    let host: String?
    let service: FaviconService
    var size = 16.0

    @State private var favicon: Favicon?

    var body: some View {
        SiteIcon(favicon: favicon, host: host, size: size)
            .task(id: host) {
                favicon = host.flatMap { $0.isEmpty ? nil : service.cachedIcon(forHost: $0) }
            }
    }
}
