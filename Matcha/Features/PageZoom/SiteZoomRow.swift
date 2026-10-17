import SwiftUI

/// Ligne « Zoom » des réglages du site (tâche 5.4) : zoom arrière, le zoom du site (un clic revient à 100 %), zoom
/// avant. Elle montre le zoom retenu pour le site de l'onglet affiché et suit les changements faits au clavier ; un
/// changement gagne toutes les pages ouvertes du site.
struct SiteZoomRow: View {
    let tab: BrowserTab
    /// Zoom par site de la fenêtre ; nil : celui de la page seule.
    let siteZooms: SiteZoomStore?

    private var site: String? {
        SiteZoomKey.key(for: tab.url)
    }

    /// Zoom du site (il peut différer un instant de celui de la page, le temps qu'elle charge son document).
    private var level: Double {
        if let siteZooms, let site {
            return siteZooms.level(forSite: site)
        }
        return tab.pageZoom
    }

    var body: some View {
        let level = level
        HStack(spacing: 8) {
            Label {
                Text("Zoom", comment: "Site settings: zoom of the pages of the website")
            } icon: {
                Image(systemName: "plus.magnifyingglass")
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            // Trois boutons séparés plutôt qu'un `ControlGroup`, qui en ferait les segments d'un seul contrôle : chacun
            // garde son état, sa bulle d'aide et son identifiant.
            HStack(spacing: 4) {
                Button { apply(.zoomOut, from: level) } label: {
                    Label { Text("Zoom Out") } icon: { Image(systemName: "minus") }
                }
                .help(Text("Zoom Out"))
                .disabled(ZoomLevels.Change.zoomOut.level(from: level) == nil)
                .accessibilityIdentifier("siteZoomOutButton")
                Button { apply(.actualSize, from: level) } label: {
                    Text(verbatim: ZoomLevels.percentText(level))
                        .monospacedDigit()
                        .frame(minWidth: 40)
                }
                .help(Text("Actual Size"))
                .disabled(ZoomLevels.isActualSize(level))
                .accessibilityLabel(Text("Actual Size"))
                .accessibilityValue(Text(verbatim: ZoomLevels.percentText(level)))
                .accessibilityIdentifier("siteZoomResetButton")
                Button { apply(.zoomIn, from: level) } label: {
                    Label { Text("Zoom In") } icon: { Image(systemName: "plus") }
                }
                .help(Text("Zoom In"))
                .disabled(ZoomLevels.Change.zoomIn.level(from: level) == nil)
                .accessibilityIdentifier("siteZoomInButton")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("siteZoomRow")
    }

    private func apply(_ change: ZoomLevels.Change, from level: Double) {
        guard let next = change.level(from: level) else {
            return
        }
        if let siteZooms, let site {
            siteZooms.setLevel(next, forSite: site)
        } else {
            tab.setPageZoom(next)
        }
    }
}
