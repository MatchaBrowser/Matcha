import SwiftUI

/// Carte aux coins arrondis qui contient la page, avec la barre d'adresse au-dessus si les réglages
/// la placent là. Un onglet qui n'a encore rien chargé, ou l'absence d'onglet, affiche un accueil.
struct ContentCard: View {
    let tabManager: TabManager
    let addressBarPosition: AddressBarPosition
    let showsNavigationButtons: Bool
    /// Action du bouton Accueil ; nil pour ne pas l'afficher.
    var goHome: (() -> Void)?
    /// Ouvre la barre de commande sur l'adresse de l'onglet affiché.
    let editAddress: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if addressBarPosition == .top {
                AddressToolbar(
                    tabManager: tabManager,
                    editAddress: editAddress,
                    showsNavigationButtons: showsNavigationButtons,
                    goHome: goHome,
                )
                Divider()
            }
            page
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: BrowserWindowView.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserWindowView.cardCornerRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }

    /// Page de l'onglet sélectionné, ou l'accueil.
    @ViewBuilder private var page: some View {
        if let tab = tabManager.selectedTab, tab.url != nil, let webView = tab.webView {
            WebView(webView: webView)
                .id(ObjectIdentifier(webView))
        } else {
            ContentUnavailableView(emptyPageTitle, systemImage: "globe", description: Text(emptyPageDescription))
                // Occupe toute la hauteur, comme la vue web : sinon la colonne entière est centrée verticalement.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Titre de l'accueil : aucun onglet sélectionné, ou onglet qui n'a encore rien chargé.
    private var emptyPageTitle: LocalizedStringKey {
        tabManager.selectedTab == nil ? "No Tabs" : "New Tab"
    }

    /// Sans onglet, ⌘T en ouvre un ; un onglet vide se remplit avec ⌘L.
    private var emptyPageDescription: LocalizedStringKey {
        tabManager.selectedTab == nil ? "Press ⌘T to search or enter an address." : "Press ⌘L to search or enter an address."
    }
}
