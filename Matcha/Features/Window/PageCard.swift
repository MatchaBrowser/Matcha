import SwiftUI

/// Carte aux coins arrondis d'un panneau : la page de l'onglet, avec la barre d'adresse au-dessus si les
/// réglages la placent là (et dessous, le panneau des réglages du site), puis la barre de recherche et le bandeau des
/// demandes de permission de la page. Un onglet qui n'a encore rien chargé, ou l'absence d'onglet, affiche un accueil ;
/// un onglet sorti de veille montre sa capture le temps du rechargement ; une page plantée plusieurs fois de suite, un
/// message pour la recharger.
struct PageCard: View {
    let tab: BrowserTab?
    /// Panneau actif d'un split : bordure de la couleur d'accentuation.
    let isMarked: Bool
    /// Onglet sélectionné (seul panneau, ou panneau actif d'un split) : il porte le panneau des réglages du site.
    var isActive = true
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
    /// Zoom par site de la fenêtre (badge du zoom de la barre d'adresse au-dessus de la page).
    var siteZooms: SiteZoomStore?

    @Environment(WindowModel.self) private var windowModel: WindowModel?

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
                    isSiteSettingsPresented: showsSiteSettings,
                    toggleSiteSettings: toggleSiteSettings,
                    siteZooms: siteZooms,
                )
                .simultaneousGesture(TapGesture().onEnded { activate() })
                Divider()
                if showsSiteSettings, let windowModel {
                    SiteSettingsPanel(model: windowModel, tabManager: windowModel.space.tabManager, maximumContentWidth: 320)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Divider()
                }
            }
            // Recherche dans la page (tâche 5.3), puis demandes de permission (tâche 5.2) : barre et bandeau poussent
            // la page. La barre reste en haut : un bandeau qui arrive ne déplace pas le champ où l'on tape.
            if let tab {
                FindBar(page: tab, activate: activate)
                PermissionBanner(prompts: tab.permissionPrompts)
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

    /// Panneau des réglages du site ouvert dans la fenêtre, montré sur la carte de l'onglet sélectionné.
    private var showsSiteSettings: Bool {
        isActive && windowModel?.isSiteSettingsPresented == true
    }

    /// Sur le panneau actif, ouvre ou ferme le panneau ; sur un autre panneau d'un split, le rend actif et l'y ouvre.
    private func toggleSiteSettings() {
        let isPresented = isActive ? !(windowModel?.isSiteSettingsPresented ?? false) : true
        activate()
        withAnimation(.easeOut(duration: 0.2)) { windowModel?.isSiteSettingsPresented = isPresented }
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
                // Onglet sorti de veille (tâche 5.6) : sa capture, le temps que la page se recharge. Elle est là dès
                // l'affichage (pas de page blanche) et s'efface en fondu.
                .overlay {
                    if let cover = tab.suspension.cover {
                        SuspendedPageCover(cover: cover)
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: tab.suspension.cover == nil)
                // Processus de la page arrêté plusieurs fois de suite (tâche 5.7) : le message, jusqu'au rechargement.
                .overlay {
                    if tab.crash.isShowingProblem {
                        PageProblemView(page: tab, activate: activate)
                    }
                }
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
