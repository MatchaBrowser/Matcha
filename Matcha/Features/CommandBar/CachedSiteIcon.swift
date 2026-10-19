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
                guard let host, !host.isEmpty else {
                    favicon = nil
                    return
                }
                // From disk, off the main thread, for a site seen in an earlier session.
                favicon = await service.loadCachedIcon(forHost: host)
            }
    }
}
