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
    @State private var isPeekHovered = false

    /// Sans effet de bord : ni tâche ni lecture de fichier.
    init(session: BrowserSession) {
        self.session = session
        // Le Space affiché est retenu d'un lancement à l'autre, sauf avec une base de test.
        let windowModel = WindowModel(session: session, defaults: session.isInMemory ? nil : .standard)
        _model = State(initialValue: windowModel)
        _commandBar = State(initialValue: CommandBarModel(windowModel: windowModel))
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

    private var isPeeking: Bool {
        !isSidebarVisible && isPeekHovered
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
                dropInset: isPeeking ? max(0, width - Self.cardMargin) : 0,
            )
            // En bas : le haut de la carte accueille la barre d'adresse (réglage) et, plus haut, la
            // barre de commande.
            .overlay(alignment: .bottom) { CopyConfirmationView(model: model.copyConfirmation) }
            .padding(isSidebarVisible ? [.top, .trailing, .bottom] : .all, Self.cardMargin)
        }
        .overlay(alignment: .leading) { sidebarOverlay }
        .overlay { CommandBarOverlay(model: commandBar, executor: commandBarExecutor, theme: theme) }
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
        .onChange(of: window) { WindowChrome.setButtonsHidden(!(isSidebarVisible || isPeeking), in: window) }
        .onChange(of: isSidebarVisible || isPeeking) { _, shown in WindowChrome.setButtonsHidden(!shown, in: window) }
        // La barre vise un onglet du Space affiché : changer de Space la ferme.
        .onChange(of: model.currentSpaceID) { commandBar.dismiss() }
        // Moteur ou suggestions changés dans les Réglages pendant que la barre reste ouverte.
        .onChange(of: commandBarSettings) { _, settings in commandBar.apply(settings) }
        .navigationTitle(session.isPrivate ? String(localized: "Private Browsing") : tabManager.selectedTab?.displayTitle ?? "Matcha")
        // Une fenêtre privée est toujours sombre, pour qu'on la reconnaisse.
        .preferredColorScheme(session.isPrivate ? .dark : nil)
        .frame(minWidth: 700, minHeight: 450)
        // Pas de `.defaultFocus` : SwiftUI rendrait le clavier à un champ dès que plus rien n'a le
        // focus, et l'enlèverait au champ de nom d'un nouveau dossier.
        // Sans onglet sélectionné, la page vide invite à ⌘T : la barre ne s'ouvre jamais d'elle-même.
        .onAppear { tabManager.loadSelectedTab() }
        .onDisappear { model.copyConfirmation.cancel() }
        .task { await session.removeOrphanDataStores() }
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
                        withAnimation(.easeOut(duration: 0.15)) { isPeekHovered = true }
                    }
                }
            if isPeeking {
                FloatingSidebar(theme: theme, width: width) { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { isPeekHovered = hovering }
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
            // `hasURL` et non `url` : la fenêtre n'est pas recalculée à chaque changement d'adresse.
            copyURL: tabManager.selectedTab?.hasURL == true ? { model.copySelectedTabURL() } : nil,
            goHome: homeURL.map { url in { goHome(to: url) } },
            spaceNames: session.spaces.map(\.record.name),
            currentSpaceIndex: model.spaceIndex,
            selectSpace: { index in withAnimation(.easeInOut(duration: 0.3)) { model.selectSpace(at: index) } },
            newSpace: { withAnimation(.easeInOut(duration: 0.3)) { model.newSpace() } },
        )
    }

    /// ⌘T et « Nouvel onglet » : la barre de commande, ou un onglet sur la page d'accueil.
    private func openCommandBarForNewTab() {
        commandBar.newTab(commandBarSettings)
    }

    /// ⌘L et la pastille d'adresse : la barre de commande sur l'adresse de l'onglet affiché.
    private func editAddress() {
        commandBar.editCurrentTab(commandBarSettings)
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarVisible.toggle()
            isPeekHovered = false
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
        if let tab = tabManager.selectedTab {
            tab.load(url)
        } else {
            tabManager.newTab(url: url)
        }
    }
}
