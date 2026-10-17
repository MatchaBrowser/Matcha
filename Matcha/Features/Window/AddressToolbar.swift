import SwiftUI

/// Barre d'adresse pleine largeur en haut d'une carte : boutons de navigation et Accueil, puis l'adresse
/// de l'onglet de cette carte.
struct AddressToolbar: View {
    let tab: BrowserTab?
    /// Ouvre la barre de commande sur l'adresse de l'onglet affiché.
    let editAddress: () -> Void
    let showsNavigationButtons: Bool
    var goHome: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            NavigationButtons(tab: tab, showsHistoryButtons: showsNavigationButtons, goHome: goHome)
            AddressPill(tab: tab, edit: editAddress)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
