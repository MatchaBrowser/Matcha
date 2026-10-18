import SwiftUI

/// Barre latérale, de haut en bas : navigation, adresse (badge du zoom, bouton des réglages du site), panneau des réglages du site
/// s'il est ouvert, favoris, épinglés, nouvel onglet, onglets du jour, panneau des téléchargements s'il est ouvert,
/// Spaces (et à gauche, le bouton des téléchargements, toujours là).
struct SidebarView: View {
    let model: WindowModel
    let tabManager: TabManager
    /// Ouvre la barre de commande sur l'adresse de l'onglet affiché (clic sur la pastille).
    let editAddress: () -> Void
    let newTab: () -> Void
    /// Faux quand la barre d'adresse est au-dessus de la page : la barre latérale n'a plus ni adresse
    /// ni boutons de navigation.
    var showsAddressBar = true
    var showsNavigationButtons = true
    /// Action du bouton Accueil ; nil pour ne pas l'afficher.
    var goHome: (() -> Void)?

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsAddressBar {
                SidebarTopBar(tab: tabManager.selectedTab, showsNavigationButtons: showsNavigationButtons, goHome: goHome)
                // Badge du zoom de l'onglet sélectionné, même quand un aperçu est ouvert (il a le sien).
                HStack(spacing: 4) {
                    AddressPill(tab: tabManager.selectedTab, edit: editAddress)
                    ZoomBadge(page: tabManager.selectedTab, siteZooms: tabManager.siteZooms)
                    SiteSettingsButton(tab: tabManager.selectedTab, isPresented: model.isSiteSettingsPresented) {
                        setSiteSettingsPresented(!model.isSiteSettingsPresented)
                    }
                }
                .animatesZoomBadge(of: tabManager.selectedTab)
                if model.isSiteSettingsPresented {
                    VStack(spacing: 0) {
                        SiteSettingsPanel(model: model, tabManager: tabManager)
                        Divider()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                SidebarTopBar(tab: tabManager.selectedTab, showsNavigationButtons: false)
            }
            FavoritesGrid(tabManager: tabManager)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    PinnedSection(tabManager: tabManager)
                    TodaySection(tabManager: tabManager, newTab: newTab)
                }
            }
            .scrollIndicators(.never)
            // Clic droit sur le fond de la barre ; les lignes ont leur propre menu.
            .contextMenu {
                Button("New Folder") { tabManager.newFolder() }
            }
            // Ouvert même vide : il le dit, et mène au dossier Téléchargements.
            if model.isDownloadsPresented {
                DownloadsPanel(downloads: downloads, scope: model.session.downloadScope) {
                    withAnimation(.easeOut(duration: 0.2)) { model.isDownloadsPresented = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            SpaceSwitcher(model: model)
                .overlay(alignment: .leading) {
                    DownloadsButton(model: model, downloads: downloads)
                }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// Le panneau des réglages du site glisse sous la pastille et pousse les onglets.
    private func setSiteSettingsPresented(_ isPresented: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { model.isSiteSettingsPresented = isPresented }
    }
}
