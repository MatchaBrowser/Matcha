import SwiftUI

/// Barre d'adresse pleine largeur en haut d'une carte : boutons de navigation et Accueil, l'adresse de l'onglet de
/// cette carte, le badge de son zoom, les boutons des extensions (tâche 6.5), puis le bouton des réglages du site.
struct AddressToolbar: View {
    let tab: BrowserTab?
    /// Ouvre la barre de commande sur l'adresse de l'onglet affiché.
    let editAddress: () -> Void
    let showsNavigationButtons: Bool
    var goHome: (() -> Void)?
    /// Panneau des réglages du site ouvert sur cette carte (bouton surligné).
    var isSiteSettingsPresented = false
    /// Bouton des réglages du site (tâche 5.2) ; nil pour ne pas l'afficher.
    var toggleSiteSettings: (() -> Void)?
    /// Zoom par site de la fenêtre, remis à 100 % par un clic sur le badge du zoom (tâche 5.4).
    var siteZooms: SiteZoomStore?
    /// Fenêtre privée : seules les extensions qui y ont accès ont leur bouton.
    var isPrivate = false

    var body: some View {
        HStack(spacing: 4) {
            NavigationButtons(tab: tab, showsHistoryButtons: showsNavigationButtons, goHome: goHome)
            AddressPill(tab: tab, edit: editAddress)
            ZoomBadge(page: tab, siteZooms: siteZooms)
            ExtensionButtonsRow(tab: tab, isPrivate: isPrivate)
            if let toggleSiteSettings {
                SiteSettingsButton(tab: tab, isPresented: isSiteSettingsPresented, action: toggleSiteSettings)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .animatesZoomBadge(of: tab)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
