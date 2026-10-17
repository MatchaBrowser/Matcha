import SwiftUI

/// Barre latérale, de haut en bas : navigation, adresse, favoris, épinglés, nouvel onglet,
/// onglets du jour, Spaces.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsAddressBar {
                SidebarTopBar(tab: tabManager.selectedTab, showsNavigationButtons: showsNavigationButtons, goHome: goHome)
                AddressPill(tabManager: tabManager, edit: editAddress)
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
            SpaceSwitcher(model: model)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}
