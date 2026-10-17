import SwiftUI

/// Carte aux coins arrondis d'un panneau : la page de l'onglet, avec la barre d'adresse au-dessus si les
/// réglages la placent là. Un onglet qui n'a encore rien chargé, ou l'absence d'onglet, affiche un accueil.
struct PageCard: View {
    let tab: BrowserTab?
    /// Panneau actif d'un split : bordure de la couleur d'accentuation.
    let isMarked: Bool
    let addressBarPosition: AddressBarPosition
    let showsNavigationButtons: Bool
    /// Action du bouton Accueil ; nil pour ne pas l'afficher.
    var goHome: (() -> Void)?
    /// Ouvre la barre de commande sur l'adresse de l'onglet affiché.
    let editAddress: () -> Void
    /// Rend ce panneau actif (clic dans sa barre d'adresse ou sur son accueil).
    let activate: () -> Void
    /// Destinataire des éléments de la barre lâchés sur la page.
    var sidebarDropTarget: (any SidebarItemDropTarget)?

    var body: some View {
        VStack(spacing: 0) {
            if addressBarPosition == .top {
                // Pastille et Accueil visent l'onglet sélectionné : ce panneau devient actif d'abord.
                AddressToolbar(
                    tab: tab,
                    editAddress: {
                        activate()
                        editAddress()
                    },
                    showsNavigationButtons: showsNavigationButtons,
                    goHome: goHome.map { home in
                        {
                            activate()
                            home()
                        }
                    },
                )
                .simultaneousGesture(TapGesture().onEnded { activate() })
                Divider()
            }
            page
                // Zone que l'aperçu (Maj+clic) voile, sous la barre d'adresse (tâche 4.4).
                .anchorPreference(key: PeekPageAreas.self, value: .bounds) { [$0] }
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: BrowserWindowView.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserWindowView.cardCornerRadius)
                .strokeBorder(isMarked ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12), lineWidth: isMarked ? 2 : 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: tab?.displayTitle ?? ""))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("pagePane")
    }

    /// « Panneau actif » sur le panneau actif d'un split.
    private var accessibilityValue: Text {
        isMarked ? Text("Active Pane", comment: "Accessibility value of the active page in a split view") : Text(verbatim: "")
    }

    /// Page de l'onglet, ou l'accueil.
    @ViewBuilder private var page: some View {
        if let tab, tab.url != nil, let webView = tab.webView {
            WebView(webView: webView, sidebarDropTarget: sidebarDropTarget)
                .id(ObjectIdentifier(webView))
        } else {
            ContentUnavailableView(emptyPageTitle, systemImage: "globe", description: Text(emptyPageDescription))
                // Occupe toute la hauteur, comme la vue web : sinon la colonne entière est centrée verticalement.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: activate)
        }
    }

    /// Titre de l'accueil : aucun onglet, ou onglet qui n'a encore rien chargé.
    private var emptyPageTitle: LocalizedStringKey {
        tab == nil ? "No Tabs" : "New Tab"
    }

    /// Sans onglet, ⌘T en ouvre un ; un onglet vide se remplit avec ⌘L.
    private var emptyPageDescription: LocalizedStringKey {
        tab == nil ? "Press ⌘T to search or enter an address." : "Press ⌘L to search or enter an address."
    }
}
