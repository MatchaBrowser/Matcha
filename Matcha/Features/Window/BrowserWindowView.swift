import AppKit
import SwiftUI
import WebKit

/// Browser window: Space background, sidebar on the left, page in a card on the right, and the command bar on top.
/// The sidebar can be hidden (⌃⌘S); it then reappears over the page when hovering the left edge. There can be several,
/// each on its Space and its tab (`WindowModel+Viewers`).
struct BrowserWindowView: View {
    /// Margin around the content card, except on the sidebar's side.
    static let cardMargin = 8.0
    static let cardCornerRadius = 10.0
    /// Width of the left edge strip whose hovering reveals the hidden sidebar.
    static let revealEdgeWidth = 8.0

    let session: BrowserSession
    /// Space shown and tab to show at opening, restored with the window.
    @Binding var state: BrowserWindowState
    @State var models: WindowModels
    @State var window: NSWindow?
    @AppStorage("sidebarWidth") private var sidebarWidth = SidebarMetrics.defaultWidth
    /// Width while the handle is dragged, for this window only: the saved width is written at the end, and the other
    /// windows follow once (review IU1).
    @State private var liveSidebarWidth: Double?
    @SceneStorage("sidebarVisible") var isSidebarVisible = true
    @AppStorage(BrowserSettings.Key.homePage) var homePage = BrowserSettings.homePage
    @AppStorage(BrowserSettings.Key.newTabPage) var newTabPage = BrowserSettings.newTabPage
    @AppStorage(BrowserSettings.Key.showsHomeButton) var showsHomeButton = BrowserSettings.showsHomeButton
    @AppStorage(BrowserSettings.Key.searchEngine) var searchEngine = BrowserSettings.searchEngine
    @AppStorage(BrowserSettings.Key.addressBarPosition) var addressBarPosition = BrowserSettings.addressBarPosition
    @AppStorage(BrowserSettings.Key.showsNavigationButtons) var showsNavigationButtons = BrowserSettings.showsNavigationButtons
    @AppStorage(BrowserSettings.Key.showsSearchSuggestions) var showsSearchSuggestions = BrowserSettings.showsSearchSuggestions
    @AppStorage(BrowserSettings.Key.searchSuggestionSource) var suggestionSource = BrowserSettings.searchSuggestionSource
    @AppStorage(BrowserSettings.Key.hiddenSidebarStyle) private var hiddenSidebarStyle = BrowserSettings.hiddenSidebarStyle
    @Environment(\.openSettings) var openSettings
    @Environment(\.openWindow) var openWindow
    /// Absent from private windows.
    @Environment(MiniWindowManager.self) var miniWindows: MiniWindowManager?
    /// Hidden sidebar shown over the page because the pointer hovers it.
    @State var isFloatingSidebarHovered = false
    /// Hovering the column of icons: shows the sidebar after a short delay (`BrowserWindowView+Compact`).
    @State var compactRevealTask: Task<Void, Never>?

    /// No side effects: no task and no file read; the models are made once (`WindowModels`).
    init(session: BrowserSession, state: Binding<BrowserWindowState> = .constant(BrowserWindowState())) {
        self.session = session
        _state = state
        _models = State(initialValue: WindowModels(
            session: session,
            spaceID: state.wrappedValue.spaceID,
            windowTabsID: state.wrappedValue.windowTabsID,
        ))
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

    /// Tabs of the window: its own, otherwise those of the displayed Space.
    var tabManager: TabManager {
        model.tabManager
    }

    /// Theme of the Space, or fixed theme of a private window.
    private var theme: SpaceTheme {
        session.isPrivate ? .privateBrowsing : space.theme
    }

    private var width: Double {
        SidebarMetrics.clampedWidth(liveSidebarWidth ?? sidebarWidth)
    }

    /// Hidden sidebar shown: hovered. The downloads panel is part of it: it reappears with it.
    private var isFloatingSidebarShown: Bool {
        !isSidebarVisible && (isFloatingSidebarHovered || model.holdsFloatingSidebar)
    }

    /// Fixed, floating or column of icons (`SidebarPresentation`).
    private var presentation: SidebarPresentation {
        SidebarPresentation(
            isSidebarVisible: isSidebarVisible,
            isFloatingSidebarShown: isFloatingSidebarShown,
            hiddenSidebarStyle: hiddenSidebarStyle,
        )
    }

    private var showsCompactSidebar: Bool {
        presentation.showsCompactSidebar
    }

    private var showsWindowButtons: Bool {
        presentation.showsWindowButtons
    }

    /// Width hidden by the floating sidebar (`floatingWidth`, nil when it isn't shown) at the start of the card, where a
    /// tab dropped doesn't join a split: the card starts after the column of icons in that mode (review ON22), after
    /// its margin otherwise.
    static func splitDropInset(floatingWidth: Double?, showsCompactSidebar: Bool) -> Double {
        guard let floatingWidth else {
            return 0
        }
        return max(0, floatingWidth - (showsCompactSidebar ? CompactSidebar.width : cardMargin))
    }

    private var cardPaddingEdges: Edge.Set {
        presentation.cardPaddingEdges
    }

    /// Downloads panel visible: open, in the fixed or floating sidebar.
    var isDownloadsPanelShown: Bool {
        model.isDownloadsPresented && (isSidebarVisible || isFloatingSidebarShown)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsCompactSidebar {
                compactTopBar
            }
            HStack(spacing: 0) {
                if isSidebarVisible {
                    sidebar
                        .frame(width: width)
                        .transition(.move(edge: .leading))
                } else if showsCompactSidebar {
                    compactSidebar
                        .transition(.move(edge: .leading))
                }
                content
            }
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
                // A private window has its own frame name (SwiftUI's).
                if !session.isPrivate {
                    BrowserWindowFrame.remember(window)
                }
                model.track(window)
                Task { self.window = window }
            }
        }
        // As in Arc, the window buttons disappear with the sidebar.
        .onChange(of: window) {
            WindowChrome.setButtonsHidden(!showsWindowButtons, in: window)
            placeAtRequestedOrigin()
        }
        .onChange(of: showsWindowButtons) { _, shown in WindowChrome.setButtonsHidden(!shown, in: window) }
        // The bar targets a tab of the displayed Space: changing Space closes it. The downloads panel, however,
        // belongs to the window: it stays open.
        .onChange(of: model.currentSpaceID) { _, id in
            commandBar.dismiss()
            state.spaceID = id
        }
        .onChange(of: model.hasNoOwnTabsLeft) { _, isEmpty in
            if isEmpty {
                WindowChrome.close(window)
            }
        }
        // “Move to…”: the window shows a Space from now on.
        .onChange(of: model.windowTabs == nil) { _, isSpaceWindow in
            if isSpaceWindow {
                state.windowTabsID = nil
            }
        }
        // A Space deleted in another window, or by sync.
        .onChange(of: session.spaces.map(\.id)) { model.spacesDidChange() }
        // Engine or suggestions changed in Settings while the bar stays open.
        .onChange(of: commandBarSettings) { _, settings in commandBar.apply(settings) }
        // The title is read by a view of its own: a new page title no longer recomputes the whole window, nor the menus
        // that follow its actions (audit H4).
        .background { WindowTitle(session: session, tabManager: tabManager, viewer: model.viewer) }
        // A private window is always dark, so that it can be recognized.
        .preferredColorScheme(session.isPrivate ? .dark : nil)
        .frame(minWidth: BrowserWindowSize.minimum.width, minHeight: BrowserWindowSize.minimum.height)
        // No `.defaultFocus`: SwiftUI would give the keyboard back to a field as soon as nothing has focus, and
        // would take it away from the name field of a new folder.
        // With no selected tab, the empty page invites ⌘T: the bar never opens by itself.
        .onAppear {
            session.showFavorites(in: space)
            model.windowDidAppear()
            tabManager.loadSelectedTab()
            // The tabs displayed by this window are never put to sleep (task 5.6).
            session.tabLifecycle.windowDidAppear(model)
        }
        .onDisappear {
            model.copyConfirmation.cancel()
            // Window closed: the peek does not stay open (sound, process) without it; its tabs return to the others.
            model.windowDidClose()
            session.tabLifecycle.windowDidDisappear(model)
        }
        .task { await session.removeOrphanDataStores() }
        // “Clear…” in the site settings (task 5.2): the alert belongs to the window.
        .modifier(SiteDataClearConfirmation(model: model))
        .modifier(ArcImportPresenter(model: model))
        // Questions of sync (first sync, mass deletion…), asked once: in the last active window, never a private one.
        .asksSyncQuestions(miniWindows?.asksSyncQuestions(in: model) == true)
        // Mini windows send their pages to this window (task 4.5).
        .linkedToMiniWindows(session: session, model: model, window: window) { [weak commandBar] in commandBar?.dismiss() }
        // Window and tabs as seen by extensions (task 6.3).
        .seenByExtensions(model: model, window: window)
        // Edit > Find on the front page (audit H1).
        .findsInPages(model: model, window: window) { [weak commandBar] in commandBar?.dismiss() }
        // Translation sessions of the window's pages (task 9.3): hidden views, and macOS's download questions.
        .background { TranslationSessionsView(host: model.translationHost) }
        .environment(model)
        .environment(model.translationHost)
        // The sidebar's rows show this window's selection.
        .environment(model.viewer)
        .focusedSceneValue(\.tabManager, tabManager)
        .focusedSceneValue(\.windowActions, windowActions)
        .focusedSceneValue(\.translationHost, model.translationHost)
    }

    /// Card of the pages, with the “URL Copied” confirmation.
    private var content: some View {
        ContentCard(
            tabManager: tabManager,
            viewer: model.viewer,
            addressBarPosition: addressBarPosition,
            showsNavigationButtons: showsNavigationButtons,
            goHome: homeButtonAction,
            editAddress: editAddress,
            // The floating sidebar covers the start of the card: the split drop zone starts after it.
            dropInset: Self.splitDropInset(floatingWidth: isFloatingSidebarShown ? width : nil, showsCompactSidebar: showsCompactSidebar),
        )
        // At the bottom: the top of the card hosts the address bar (setting) and, higher up, the command bar.
        .overlay(alignment: .bottom) { CopyConfirmationView(model: model.copyConfirmation) }
        .padding(cardPaddingEdges, Self.cardMargin)
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

    /// Visible sidebar: width handle. Hidden sidebar: hover strip (the column of icons, which is on the edge, plays
    /// that part), and the floating sidebar.
    @ViewBuilder private var sidebarOverlay: some View {
        if isSidebarVisible {
            // Above the sidebar and the card, straddling their boundary.
            SidebarResizeHandle(width: $sidebarWidth, liveWidth: $liveSidebarWidth)
                .offset(x: width - SidebarResizeHandle.thickness / 2)
        } else {
            if !showsCompactSidebar {
                Color.clear
                    .frame(width: Self.revealEdgeWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            withMotion(.easeOut(duration: 0.15)) { isFloatingSidebarHovered = true }
                        }
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
