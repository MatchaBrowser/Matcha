import AppKit
import SwiftUI
import WebKit

/// Browser window: Space background, sidebar on the left, page in a card on the right, and the command bar on top.
/// The sidebar can be hidden (⌃⌘S); it then reappears over the page when hovering the left edge.
struct BrowserWindowView: View {
    /// Margin around the content card, except on the sidebar's side.
    static let cardMargin = 8.0
    static let cardCornerRadius = 10.0
    /// Width of the left edge strip whose hovering reveals the hidden sidebar.
    static let revealEdgeWidth = 8.0

    let session: BrowserSession
    @State private var models: WindowModels
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
    /// Hidden sidebar shown over the page because the pointer hovers it.
    @State private var isFloatingSidebarHovered = false

    /// No side effects: no task and no file read; the models are made once (`WindowModels`).
    init(session: BrowserSession) {
        self.session = session
        _models = State(initialValue: WindowModels(session: session))
    }

    private var model: WindowModel {
        models.window
    }

    private var commandBar: CommandBarModel {
        models.commandBar
    }

    /// Displayed Space.
    private var space: SpaceSession {
        model.space
    }

    /// Tabs of the displayed Space.
    private var tabManager: TabManager {
        space.tabManager
    }

    /// Theme of the Space, or fixed theme of a private window.
    private var theme: SpaceTheme {
        session.isPrivate ? .privateBrowsing : space.theme
    }

    private var width: Double {
        SidebarMetrics.clampedWidth(sidebarWidth)
    }

    /// Hidden sidebar shown: hovered. The downloads panel is part of it: it reappears with it.
    private var isFloatingSidebarShown: Bool {
        !isSidebarVisible && isFloatingSidebarHovered
    }

    /// Downloads panel visible: open, in the fixed or floating sidebar.
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
                // The floating sidebar covers the start of the card: the split drop zone starts after it.
                dropInset: isFloatingSidebarShown ? max(0, width - Self.cardMargin) : 0,
            )
            // At the bottom: the top of the card hosts the address bar (setting) and, higher up, the command bar.
            .overlay(alignment: .bottom) { CopyConfirmationView(model: model.copyConfirmation) }
            .padding(isSidebarVisible ? [.top, .trailing, .bottom] : .all, Self.cardMargin)
        }
        .overlay(alignment: .leading) { sidebarOverlay }
        .overlay {
            CommandBarOverlay(model: commandBar, submit: commandBarExecutor.submit, cancel: commandBarExecutor.cancel, theme: theme)
        }
        .ignoresSafeArea()
        .background {
            // Dragging the background (empty areas) moves the window.
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
        // As in Arc, the window buttons disappear with the sidebar.
        .onChange(of: window) { WindowChrome.setButtonsHidden(!(isSidebarVisible || isFloatingSidebarShown), in: window) }
        .onChange(of: isSidebarVisible || isFloatingSidebarShown) { _, shown in WindowChrome.setButtonsHidden(!shown, in: window) }
        // The bar targets a tab of the displayed Space: changing Space closes it. The downloads panel, however,
        // belongs to the window: it stays open.
        .onChange(of: model.currentSpaceID) {
            commandBar.dismiss()
        }
        // Engine or suggestions changed in Settings while the bar stays open.
        .onChange(of: commandBarSettings) { _, settings in commandBar.apply(settings) }
        .navigationTitle(session.isPrivate ? String(localized: "Private Browsing") : tabManager.selectedTab?.displayTitle ?? "Matcha")
        // A private window is always dark, so that it can be recognized.
        .preferredColorScheme(session.isPrivate ? .dark : nil)
        .frame(minWidth: 700, minHeight: 450)
        // No `.defaultFocus`: SwiftUI would give the keyboard back to a field as soon as nothing has focus, and
        // would take it away from the name field of a new folder.
        // With no selected tab, the empty page invites ⌘T: the bar never opens by itself.
        .onAppear {
            session.showFavorites(in: space)
            tabManager.loadSelectedTab()
            // The tabs displayed by this window are never put to sleep (task 5.6).
            session.tabLifecycle.windowDidAppear(model)
        }
        .onDisappear {
            model.copyConfirmation.cancel()
            // Window closed: the peek does not stay open (sound, process) without it.
            tabManager.closePeek()
            session.tabLifecycle.windowDidDisappear(model)
        }
        .task { await session.removeOrphanDataStores() }
        // Two windows on two Spaces of the same profile: the active window holds the favorites (and saves them).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window, notification.object as? NSWindow === window {
                session.showFavorites(in: space)
            }
        }
        // “Clear…” in the site settings (task 5.2): the alert belongs to the window.
        .modifier(SiteDataClearConfirmation(model: model))
        .modifier(ArcImportPresenter(model: model))
        // Mini windows send their pages to this window (task 4.5).
        .linkedToMiniWindows(session: session, model: model, window: window) { [commandBar] in commandBar.dismiss() }
        // Window and tabs as seen by extensions (task 6.3).
        .seenByExtensions(model: model, window: window)
        // Edit > Find on the front page (audit H1).
        .findsInPages(model: model, window: window) { [commandBar] in commandBar.dismiss() }
        .environment(model)
        .focusedSceneValue(\.tabManager, tabManager)
        .focusedSceneValue(\.windowActions, windowActions)
    }

    /// Sidebar of the displayed Space; changing Space slides it like a page.
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

    /// Visible sidebar: width handle. Hidden sidebar: hover strip, and the floating sidebar.
    @ViewBuilder private var sidebarOverlay: some View {
        if isSidebarVisible {
            // Above the sidebar and the card, straddling their boundary.
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

    /// Settings read each time the command bar opens, and followed while it is open.
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
            // `hasURL` and not `url`: the window is not recomputed on each address change.
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

    /// ⌘1 to ⌘9, ⌃⇥ and ⌃⇧⇥: like a click in the sidebar, which closes the command bar and the peek (even on the
    /// tab already displayed).
    private func showTab(_ tab: BrowserTab) {
        commandBar.dismiss()
        tabManager.closePeek()
        TabActivation.activate(tab, in: tabManager)
    }

    /// ⌘T and “New Tab”: the command bar, or a tab on the home page.
    private func openCommandBarForNewTab() {
        // A single floating layer: the command bar closes the peek.
        tabManager.closePeek()
        commandBar.newTab(commandBarSettings)
    }

    /// ⌘L and the address pill: the command bar on the address of the displayed tab.
    private func editAddress() {
        // A single floating layer: the command bar closes the peek.
        tabManager.closePeek()
        commandBar.editCurrentTab(commandBarSettings)
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarVisible.toggle()
            isFloatingSidebarHovered = false
        }
    }

    /// ⌥⌘L: hides the downloads panel if it is visible; otherwise shows the hidden sidebar, then opens it.
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

    /// Action of the Home button, if it is displayed and a home page is set.
    private var homeButtonAction: (() -> Void)? {
        showsHomeButton ? windowActions.goHome : nil
    }

    private var homeURL: URL? {
        BrowserSettings.homeURL(from: homePage, searchEngine: searchEngine)
    }

    /// Loads the home page in the selected tab, or in a new tab if there is none.
    private func goHome(to url: URL) {
        tabManager.closePeek()
        if let tab = tabManager.selectedTab {
            tab.load(url)
        } else {
            tabManager.newTab(url: url)
        }
    }
}
