import SwiftUI

/// Contenu d'une fenêtre de connexion (tâche 5.8) : la barre d'adresse en lecture seule, le bandeau des demandes de
/// permission de la page (tâche 5.2), puis la page (conteneur AppKit, jamais recréé), ou le message d'une page plantée
/// plusieurs fois de suite (tâche 5.7). Ni boutons de navigation ni saisie d'adresse. Le titre de la fenêtre suit
/// celui de la page.
struct PopupWindowView: View {
    let controller: PopupWindowController

    private var tab: BrowserTab {
        controller.tab
    }

    var body: some View {
        VStack(spacing: 0) {
            PopupAddressBar(page: tab)
            PermissionBanner(prompts: tab.permissionPrompts)
            ZStack {
                MiniWebViewContainerView(container: controller.container)
                if tab.crash.isShowingProblem {
                    PageProblemView(page: tab)
                }
            }
        }
        .background(.background)
        // Titre lu aussi par VoiceOver, Mission Control et le menu Fenêtre ; rien avant que la page ait une adresse.
        .onChange(of: windowTitle, initial: true) { _, title in controller.window.title = title }
    }

    private var windowTitle: String {
        tab.hasURL ? tab.displayTitle : ""
    }
}
