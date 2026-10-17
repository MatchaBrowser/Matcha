import SwiftUI

/// Icône d'un site sans onglet ouvert (adresse tapée, historique) : celle déjà en cache pour son
/// domaine, sinon l'initiale. Ne télécharge rien.
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
