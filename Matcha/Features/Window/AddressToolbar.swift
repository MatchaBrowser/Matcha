import SwiftUI

/// Barre d'adresse pleine largeur en haut de la carte : boutons de navigation et Accueil, puis l'adresse.
struct AddressToolbar: View {
    let tabManager: TabManager
    /// Ouvre la barre de commande sur l'adresse de l'onglet affiché.
    let editAddress: () -> Void
    let showsNavigationButtons: Bool
    var goHome: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            NavigationButtons(tab: tabManager.selectedTab, showsHistoryButtons: showsNavigationButtons, goHome: goHome)
            AddressPill(tabManager: tabManager, edit: editAddress)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
