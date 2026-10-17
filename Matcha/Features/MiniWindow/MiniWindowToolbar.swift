import SwiftUI

/// Barre d'outils d'une mini-fenêtre : fermer, précédent (s'il y a une page avant), l'adresse (un clic la
/// modifie, comme ⌘L) et le zoom de la page, une zone vide qui déplace la fenêtre, puis « Ouvrir dans ‹Space› ».
struct MiniWindowToolbar: View {
    static let height = 40.0

    let tab: BrowserTab
    /// Space visé par le bouton (et par ⌘O) ; suit le Space affiché par la fenêtre principale.
    let target: SpaceSession
    /// Zoom par site de la session principale, remis à 100 % par un clic sur le badge du zoom (tâche 5.4).
    let siteZooms: SiteZoomStore?
    let close: () -> Void
    let editAddress: () -> Void
    let openInSpace: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button("Close Mini Window", systemImage: "xmark", action: close)
                .help("Close Mini Window")
                .accessibilityIdentifier("miniWindowClose")
            if tab.canGoBack {
                Button("Back", systemImage: "arrow.left") { tab.goBack() }
            }
            AddressPill(tab: tab, edit: editAddress)
                .frame(minWidth: 120, maxWidth: 280)
            ZoomBadge(page: tab, siteZooms: siteZooms)
            // Le fond de la fenêtre se voit ici : tirer sur cette zone déplace la fenêtre.
            Spacer(minLength: 12)
            openButton
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .animatesZoomBadge(of: tab)
        .padding(.horizontal, 8)
        .frame(height: Self.height)
    }

    /// « Ouvrir dans ‹Space› », avec l'icône du Space ; le nom se tronque avant que le bouton ne rétrécisse.
    private var openButton: some View {
        Button(action: openInSpace) {
            HStack(spacing: 6) {
                Image(systemName: target.record.symbol)
                Text("Open in \(target.record.name)", comment: "Mini window button; %@ is the name of the Space")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(maxWidth: 190)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(tab.url == nil)
        .accessibilityLabel(Text("Open in Space"))
        .accessibilityValue(Text(verbatim: target.record.name))
        .accessibilityIdentifier("miniWindowOpenInSpace")
    }
}
