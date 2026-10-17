import SwiftUI

/// Contenu d'une mini-fenêtre : fond aux couleurs du Space visé, barre d'outils minimale, page dans une carte, et
/// la barre de commande sous la barre d'outils.
struct MiniWindowView: View {
    static let cardMargin = 6.0
    static let cardCornerRadius = 8.0

    let controller: MiniWindowController
    let manager: MiniWindowManager

    @AppStorage(BrowserSettings.Key.searchEngine) private var searchEngine = BrowserSettings.searchEngine
    @AppStorage(BrowserSettings.Key.showsSearchSuggestions) private var showsSearchSuggestions = BrowserSettings.showsSearchSuggestions
    @Environment(\.openWindow) private var openWindow

    private var tab: BrowserTab {
        controller.tab
    }

    /// Space où « Ouvrir dans … » enverrait la page maintenant.
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
                openInSpace: { manager.openInSpace(controller) { openWindow(id: MatchaApp.browserWindowID) } },
            )
            page
                .background(.background)
                .clipShape(.rect(cornerRadius: Self.cardCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cardCornerRadius)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                }
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
            // Tirer sur le fond (zones vides de la barre) déplace la fenêtre.
            SpaceBackground(theme: target.theme)
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
        // Titre invisible, lu par VoiceOver, Mission Control et le menu Fenêtre.
        .onChange(of: windowTitle, initial: true) { _, title in controller.panel.title = title }
        // Moteur ou suggestions changés dans les Réglages pendant que la barre reste ouverte.
        .onChange(of: settings) { _, settings in controller.commandBar.apply(settings) }
    }

    /// Page de la mini-fenêtre (conteneur AppKit, jamais recréé), ou une invite tant qu'elle n'a rien chargé ; au-dessus,
    /// sa barre de recherche (tâche 5.3) et le bandeau de ses demandes de permission (tâche 5.2).
    private var page: some View {
        VStack(spacing: 0) {
            FindBar(page: tab)
            PermissionBanner(prompts: tab.permissionPrompts)
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
                }
            }
        }
    }

    private var windowTitle: String {
        tab.url == nil ? String(localized: "Mini Window") : tab.displayTitle
    }

    private var settings: CommandBarSettings {
        CommandBarSettings(searchEngine: searchEngine, newTabPage: .blank, homePage: "", showsSearchSuggestions: showsSearchSuggestions)
    }
}
