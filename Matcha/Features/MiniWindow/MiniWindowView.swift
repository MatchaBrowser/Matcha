import SwiftUI

/// Content of a mini window: background in the target Space's colors, minimal toolbar, page in a card, and the
/// command bar below the toolbar.
struct MiniWindowView: View {
    static let cardMargin = 6.0
    static let cardCornerRadius = 8.0

    let controller: MiniWindowController
    let manager: MiniWindowManager

    @AppStorage(BrowserSettings.Key.searchEngine) private var searchEngine = BrowserSettings.searchEngine
    @AppStorage(BrowserSettings.Key.showsSearchSuggestions) private var showsSearchSuggestions = BrowserSettings.showsSearchSuggestions
    @AppStorage(BrowserSettings.Key.searchSuggestionSource) private var suggestionSource = BrowserSettings.searchSuggestionSource
    @Environment(\.openWindow) private var openWindow

    private var tab: BrowserTab {
        controller.tab
    }

    /// Space where “Open in …” would send the page now.
    private var target: SpaceSession {
        manager.defaultTarget(profileID: controller.profileID)
    }

    var body: some View {
        VStack(spacing: 0) {
            MiniWindowToolbar(
                tab: tab,
                target: target,
                siteZooms: manager.siteZooms,
                close: controller.close,
                editAddress: { controller.showCommandBar(.editAddress) },
                openInSpace: {
                    manager.openInSpace(controller) {
                        manager.reopenMainWindow { openWindow(id: MatchaApp.browserWindowID) }
                    }
                },
            )
            page
                .pageCardFrame(cornerRadius: Self.cardCornerRadius)
                .overlay(alignment: .bottom) { CopyConfirmationView(model: controller.copyConfirmation) }
                .padding([.leading, .trailing, .bottom], Self.cardMargin)
        }
        .overlay {
            CommandBarOverlay(
                model: controller.commandBar,
                submit: controller.submit,
                cancel: controller.cancelCommandBar,
                theme: target.theme,
                placement: .belowToolbar(top: MiniWindowToolbar.height),
            )
        }
        .ignoresSafeArea()
        .background {
            // Dragging the background (empty areas of the bar) moves the window.
            SpaceBackground(theme: target.theme)
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
        // Invisible title, read by VoiceOver, Mission Control and the Window menu; followed apart (review IU4).
        .background { MiniWindowTitle(tab: tab, panel: controller.panel) }
        // Translation sessions of the page (task 9.3).
        .background { TranslationSessionsView(host: controller.translationHost) }
        .environment(controller.translationHost)
        // Engine or suggestions changed in Settings while the bar stays open.
        .onChange(of: settings) { _, settings in controller.commandBar.apply(settings) }
    }

    /// The mini window's page (AppKit container, never recreated), or a prompt as long as it has loaded nothing, or
    /// the message of a page that crashed several times in a row (task 5.7); above it, its find bar (task 5.3), the
    /// banner of its permission requests (task 5.2) and that of the files a local page can't show (review WB11).
    private var page: some View {
        VStack(spacing: 0) {
            FindBar(page: tab)
            PermissionBanner(prompts: tab.permissionPrompts)
            LocalFilesBanner(page: tab)
            ZStack {
                MiniWebViewContainerView(container: controller.container)
                if tab.url == nil {
                    ContentUnavailableView(
                        "Mini Window",
                        systemImage: "macwindow",
                        description: Text("Press ⌘L to search or enter an address."),
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                } else if tab.crash.isShowingProblem {
                    PageProblemView(page: tab)
                } else if let error = tab.loadFailure.error {
                    PageLoadErrorView(page: tab, error: error)
                }
            }
        }
    }

    private var settings: CommandBarSettings {
        CommandBarSettings(
            searchEngine: searchEngine,
            newTabPage: .blank,
            homePage: "",
            showsSearchSuggestions: showsSearchSuggestions,
            suggestionSource: suggestionSource,
        )
    }
}

/// The mini window's title, the page's: read in this small view only, a new title doesn't recompute the mini window
/// (review IU4).
private struct MiniWindowTitle: View {
    let tab: BrowserTab
    let panel: NSWindow

    var body: some View {
        Color.clear
            .onChange(of: title, initial: true) { _, title in panel.title = title }
            .accessibilityHidden(true)
    }

    private var title: String {
        tab.url == nil ? String(localized: "Mini Window") : tab.pageTitle
    }
}
