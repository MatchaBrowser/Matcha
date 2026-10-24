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
    @State var models: WindowModels
    @State var window: NSWindow?
    @AppStorage("sidebarWidth") private var sidebarWidth = SidebarMetrics.defaultWidth
    @SceneStorage("sidebarVisible") var isSidebarVisible = true
    @AppStorage(BrowserSettings.Key.homePage) var homePage = BrowserSettings.homePage
    @AppStorage(BrowserSettings.Key.newTabPage) var newTabPage = BrowserSettings.newTabPage
    @AppStorage(BrowserSettings.Key.showsHomeButton) var showsHomeButton = BrowserSettings.showsHomeButton
    @AppStorage(BrowserSettings.Key.searchEngine) var searchEngine = BrowserSettings.searchEngine
    @AppStorage(BrowserSettings.Key.addressBarPosition) private var addressBarPosition = BrowserSettings.addressBarPosition
    @AppStorage(BrowserSettings.Key.showsNavigationButtons) private var showsNavigationButtons = BrowserSettings.showsNavigationButtons
    @AppStorage(BrowserSettings.Key.showsSearchSuggestions) var showsSearchSuggestions = BrowserSettings.showsSearchSuggestions
    @Environment(\.openSettings) var openSettings
    /// Hidden sidebar shown over the page because the pointer hovers it.
    @State var isFloatingSidebarHovered = false

    /// No side effects: no task and no file read; the models are made once (`WindowModels`).
    init(session: BrowserSession) {
        self.session = session
        _models = State(initialValue: WindowModels(session: session))
    }

    var model: WindowModel {
        models.window
    }

    var commandBar: CommandBarModel {
        models.commandBar
    }

    /// Displayed Space.
    private var space: SpaceSession {
        model.space
    }

    /// Tabs of the displayed Space.
    var tabManager: TabManager {
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
    var isDownloadsPanelShown: Bool {
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
            // Dragging the background (empty areas) moves the window; at the top, a double click zooms it.
            SpaceBackground(theme: theme)
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
                .overlay(alignment: .top) {
                    TitleBarArea()
                        .frame(height: SidebarTopBar.height)
                }
                // Up to the top edge: otherwise the strip starts below the hidden title bar's safe area.
                .ignoresSafeArea()
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
        // The title is read by a view of its own: a new page title no longer recomputes the whole window, nor the menus
        // that follow its actions (audit H4).
        .background { WindowTitle(session: session, tabManager: tabManager) }
        // A private window is always dark, so that it can be recognized.
        .preferredColorScheme(session.isPrivate ? .dark : nil)
        .frame(minWidth: BrowserWindowSize.minimum.width, minHeight: BrowserWindowSize.minimum.height)
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
        // Questions of sync (first sync, mass deletion…), answered in the main window.
        .asksSyncQuestions()
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
                withMotion(.easeInOut(duration: 0.3)) { model.selectAdjacentSpace(direction) }
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
                        withMotion(.easeOut(duration: 0.15)) { isFloatingSidebarHovered = true }
                    }
                }
            if isFloatingSidebarShown {
                FloatingSidebar(theme: theme, width: width) { hovering in
                    withMotion(.easeOut(duration: 0.15)) { isFloatingSidebarHovered = hovering }
                } content: {
                    sidebar
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }
}
