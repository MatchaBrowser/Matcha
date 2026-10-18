import AppKit
import SwiftUI
import WebKit

/// Fenêtre de navigation : fond du Space, barre latérale à gauche, page dans une carte à droite, et la
/// barre de commande par-dessus. La barre latérale peut être masquée (⌘S) ; elle réapparaît alors
/// par-dessus la page au survol du bord gauche.
struct BrowserWindowView: View {
    /// Marge autour de la carte de contenu, sauf du côté de la barre latérale.
    static let cardMargin = 8.0
    static let cardCornerRadius = 10.0
    /// Largeur de la bande du bord gauche dont le survol fait apparaître la barre masquée.
    static let revealEdgeWidth = 8.0

    let session: BrowserSession
    @State private var model: WindowModel
    @State private var commandBar: CommandBarModel
    @State private var window: NSWindow?
    @AppStorage("sidebarWidth") private var sidebarWidth = SidebarMetrics.defaultWidth
    @SceneStorage("sidebarVisible") private var isSidebarVisible = true
    @AppStorage(BrowserSettings.Key.homePage) private var homePage = BrowserSettings.homePage
    @AppStorage(BrowserSettings.Key.newTabPage) private var newTabPage = BrowserSettings.newTabPage
    @AppStorage(BrowserSettings.Key.showsHomeButton) private var showsHomeButton = BrowserSettings.showsHomeButton
    @AppStorage(BrowserSettings.Key.searchEngine) private var searchEngine = BrowserSettings.searchEngine
    @AppStorage(BrowserSettings.Key.addressBarPosition) private var addressBarPosition = BrowserSettings.addressBarPosition
    @AppStorage(BrowserSettings.Key.showsNavigationButtons) private var showsNavigationButtons = BrowserSettings.showsNavigationButtons
    @AppStorage(BrowserSettings.Key.showsSearchSuggestions) private var showsSearchSuggestions = BrowserSettings.showsSearchSuggestions
    @Environment(\.openSettings) private var openSettings
    /// Barre masquée affichée par-dessus la page parce que le pointeur la survole.
    @State private var isFloatingSidebarHovered = false

    /// Sans effet de bord : ni tâche ni lecture de fichier.
    init(session: BrowserSession) {
        self.session = session
        // Le Space affiché est retenu d'un lancement à l'autre, sauf avec une base de test.
        let windowModel = WindowModel(session: session, defaults: session.isInMemory ? nil : .standard)
        _model = State(initialValue: windowModel)
        // Historique du profil du Space affiché, relu à chaque frappe ; aucun pour une fenêtre privée.
        let history = session.history.map { store in ProfileHistory(store: store) { windowModel.space.record.profile?.id } }
        _commandBar = State(initialValue: CommandBarModel(windowModel: windowModel, history: history))
    }

    /// Space affiché.
    private var space: SpaceSession {
        model.space
    }

    /// Onglets du Space affiché.
    private var tabManager: TabManager {
        space.tabManager
    }

    /// Thème du Space, ou thème fixe d'une fenêtre privée.
    private var theme: SpaceTheme {
        session.isPrivate ? .privateBrowsing : space.theme
    }

    private var width: Double {
        SidebarMetrics.clampedWidth(sidebarWidth)
    }

    /// Barre masquée affichée : survolée. Le panneau des téléchargements en fait partie : il réapparaît avec elle.
    private var isFloatingSidebarShown: Bool {
        !isSidebarVisible && isFloatingSidebarHovered
    }

    /// Panneau des téléchargements visible : ouvert, dans la barre fixe ou flottante.
    private var isDownloadsPanelShown: Bool {
        model.isDownloadsPresented && (isSidebarVisible || isFloatingSidebarShown)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: width)
                    .transition(.move(edge: .leading))
            }
            ContentCard(
                tabManager: tabManager,
                addressBarPosition: addressBarPosition,
                showsNavigationButtons: showsNavigationButtons,
                goHome: homeButtonAction,
                editAddress: editAddress,
                // La barre flottante couvre le début de la carte : la zone de dépôt du split commence après.
                dropInset: isFloatingSidebarShown ? max(0, width - Self.cardMargin) : 0,
            )
            // En bas : le haut de la carte accueille la barre d'adresse (réglage) et, plus haut, la
            // barre de commande.
            .overlay(alignment: .bottom) { CopyConfirmationView(model: model.copyConfirmation) }
            .padding(isSidebarVisible ? [.top, .trailing, .bottom] : .all, Self.cardMargin)
        }
        .overlay(alignment: .leading) { sidebarOverlay }
        .overlay {
            CommandBarOverlay(model: commandBar, submit: commandBarExecutor.submit, cancel: commandBarExecutor.cancel, theme: theme)
        }
        .ignoresSafeArea()
        .background {
            // Tirer sur le fond (zones vides) déplace la fenêtre.
            SpaceBackground(theme: theme)
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
        .background {
            WindowAccessor { window in
                WindowChrome.configure(window)
                Task { self.window = window }
            }
        }
        // Comme dans Arc, les boutons de la fenêtre disparaissent avec la barre latérale.
        .onChange(of: window) { WindowChrome.setButtonsHidden(!(isSidebarVisible || isFloatingSidebarShown), in: window) }
        .onChange(of: isSidebarVisible || isFloatingSidebarShown) { _, shown in WindowChrome.setButtonsHidden(!shown, in: window) }
        // La barre vise un onglet du Space affiché : changer de Space la ferme. Le panneau des téléchargements, lui,
        // appartient à la fenêtre : il reste ouvert.
        .onChange(of: model.currentSpaceID) {
            commandBar.dismiss()
        }
        // Moteur ou suggestions changés dans les Réglages pendant que la barre reste ouverte.
        .onChange(of: commandBarSettings) { _, settings in commandBar.apply(settings) }
        .navigationTitle(session.isPrivate ? String(localized: "Private Browsing") : tabManager.selectedTab?.displayTitle ?? "Matcha")
        // Une fenêtre privée est toujours sombre, pour qu'on la reconnaisse.
        .preferredColorScheme(session.isPrivate ? .dark : nil)
        .frame(minWidth: 700, minHeight: 450)
        // Pas de `.defaultFocus` : SwiftUI rendrait le clavier à un champ dès que plus rien n'a le
        // focus, et l'enlèverait au champ de nom d'un nouveau dossier.
        // Sans onglet sélectionné, la page vide invite à ⌘T : la barre ne s'ouvre jamais d'elle-même.
        .onAppear {
            session.showFavorites(in: space)
            tabManager.loadSelectedTab()
            // Les onglets affichés par cette fenêtre ne sont jamais mis en veille (tâche 5.6).
            session.tabLifecycle.windowDidAppear(model)
        }
        .onDisappear {
            model.copyConfirmation.cancel()
            // Fenêtre fermée : l'aperçu ne reste pas ouvert (son, processus) sans elle.
            tabManager.closePeek()
            session.tabLifecycle.windowDidDisappear(model)
        }
        .task { await session.removeOrphanDataStores() }
        // Deux fenêtres sur deux Spaces d'un même profil : la fenêtre active tient les favoris (et les enregistre).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window, notification.object as? NSWindow === window {
                session.showFavorites(in: space)
            }
        }
        // « Effacer… » des réglages du site (tâche 5.2) : l'alerte appartient à la fenêtre.
        .modifier(SiteDataClearConfirmation(model: model))
        .modifier(ArcImportPresenter(model: model))
        // Les mini-fenêtres envoient leurs pages dans cette fenêtre (tâche 4.5).
        .linkedToMiniWindows(session: session, model: model, window: window) { [commandBar] in commandBar.dismiss() }
        // Fenêtre et onglets vus par les extensions (tâche 6.3).
        .seenByExtensions(model: model, window: window)
        .environment(model)
        .focusedSceneValue(\.tabManager, tabManager)
        .focusedSceneValue(\.windowActions, windowActions)
    }

    /// Barre latérale du Space affiché ; changer de Space la fait glisser comme une page.
    private var sidebar: some View {
        ZStack {
            SidebarView(
                model: model,
                tabManager: tabManager,
                editAddress: editAddress,
                newTab: openCommandBarForNewTab,
                showsAddressBar: addressBarPosition == .sidebar,
                showsNavigationButtons: showsNavigationButtons,
                goHome: homeButtonAction,
                sidebarToggle: SidebarToggle(isVisible: isSidebarVisible, toggle: toggleSidebar),
            )
            .id(space.id)
            .transition(.push(from: model.transitionEdge))
        }
        .clipped()
        .background {
            SpaceSwipeArea { direction in
                withAnimation(.easeInOut(duration: 0.3)) { model.selectAdjacentSpace(direction) }
            }
        }
    }

    /// Barre visible : poignée de largeur. Barre masquée : bande de survol, et la barre flottante.
    @ViewBuilder private var sidebarOverlay: some View {
        if isSidebarVisible {
            // Au-dessus de la barre et de la carte, à cheval sur leur frontière.
            SidebarResizeHandle(width: $sidebarWidth)
                .offset(x: width - SidebarResizeHandle.thickness / 2)
        } else {
            Color.clear
                .frame(width: Self.revealEdgeWidth)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        withAnimation(.easeOut(duration: 0.15)) { isFloatingSidebarHovered = true }
                    }
                }
            if isFloatingSidebarShown {
                FloatingSidebar(theme: theme, width: width) { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { isFloatingSidebarHovered = hovering }
                } content: {
                    sidebar
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    /// Réglages lus à chaque ouverture de la barre de commande, et suivis pendant qu'elle est ouverte.
    private var commandBarSettings: CommandBarSettings {
        CommandBarSettings(
            searchEngine: searchEngine,
            newTabPage: newTabPage,
            homePage: homePage,
            showsSearchSuggestions: showsSearchSuggestions,
        )
    }

    private var commandBarExecutor: CommandBarExecutor {
        CommandBarExecutor(model: commandBar, window: window, openSettings: { openSettings() })
    }

    private var windowActions: WindowActions {
        WindowActions(
            newTab: openCommandBarForNewTab,
            editAddress: editAddress,
            isCommandBarPresented: commandBar.isPresented,
            closeCommandBar: commandBarExecutor.cancel,
            toggleSidebar: toggleSidebar,
            isSidebarVisible: isSidebarVisible,
            toggleDownloads: toggleDownloads,
            isDownloadsPanelShown: isDownloadsPanelShown,
            // `hasURL` et non `url` : la fenêtre n'est pas recalculée à chaque changement d'adresse.
            copyURL: tabManager.frontTab?.hasURL == true ? { model.copySelectedTabURL() } : nil,
            goHome: homeURL.map { url in { goHome(to: url) } },
            spaceNames: session.spaces.map(\.record.name),
            currentSpaceIndex: model.spaceIndex,
            selectSpace: { index in withAnimation(.easeInOut(duration: 0.3)) { model.selectSpace(at: index) } },
            newSpace: { withAnimation(.easeInOut(duration: 0.3)) { model.newSpace() } },
            showTab: showTab,
            isPrivate: session.isPrivate,
            importFromArc: session.isPrivate ? nil : { model.arcImport.chooseFile(in: window) },
        )
    }

    /// ⌘1 à ⌘9, ⌃⇥ et ⌃⇧⇥ : comme un clic dans la barre, qui ferme la barre de commande et l'aperçu (même
    /// sur l'onglet déjà affiché).
    private func showTab(_ tab: BrowserTab) {
        commandBar.dismiss()
        tabManager.closePeek()
        TabActivation.activate(tab, in: tabManager)
    }

    /// ⌘T et « Nouvel onglet » : la barre de commande, ou un onglet sur la page d'accueil.
    private func openCommandBarForNewTab() {
        // Une seule couche flottante : la barre de commande ferme l'aperçu.
        tabManager.closePeek()
        commandBar.newTab(commandBarSettings)
    }

    /// ⌘L et la pastille d'adresse : la barre de commande sur l'adresse de l'onglet affiché.
    private func editAddress() {
        // Une seule couche flottante : la barre de commande ferme l'aperçu.
        tabManager.closePeek()
        commandBar.editCurrentTab(commandBarSettings)
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarVisible.toggle()
            isFloatingSidebarHovered = false
        }
    }

    /// ⌥⌘L : masque le panneau des téléchargements s'il est visible ; sinon affiche la barre masquée, puis l'ouvre.
    private func toggleDownloads() {
        let show = !isDownloadsPanelShown
        withAnimation(.easeInOut(duration: 0.2)) {
            if show, !isSidebarVisible {
                isSidebarVisible = true
                isFloatingSidebarHovered = false
            }
            model.isDownloadsPresented = show
        }
    }

    /// Action du bouton Accueil, s'il est affiché et qu'une page d'accueil est réglée.
    private var homeButtonAction: (() -> Void)? {
        showsHomeButton ? windowActions.goHome : nil
    }

    private var homeURL: URL? {
        BrowserSettings.homeURL(from: homePage, searchEngine: searchEngine)
    }

    /// Charge la page d'accueil dans l'onglet sélectionné, ou dans un nouvel onglet s'il n'y en a pas.
    private func goHome(to url: URL) {
        tabManager.closePeek()
        if let tab = tabManager.selectedTab {
            tab.load(url)
        } else {
            tabManager.newTab(url: url)
        }
    }
}
