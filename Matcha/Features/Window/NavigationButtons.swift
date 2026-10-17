import SwiftUI

/// Précédent, suivant, recharger (ou arrêter) pour l'onglet, puis Accueil si demandé.
/// Le conteneur choisit le style des boutons.
struct NavigationButtons: View {
    let tab: BrowserTab?
    var showsHistoryButtons = true
    /// Action du bouton Accueil ; nil pour ne pas l'afficher.
    var goHome: (() -> Void)?

    var body: some View {
        if showsHistoryButtons {
            Button("Back", systemImage: "arrow.left") { tab?.goBack() }
                .disabled(tab?.canGoBack != true)
            Button("Forward", systemImage: "arrow.right") { tab?.goForward() }
                .disabled(tab?.canGoForward != true)
            if tab?.isLoading == true {
                Button("Stop", systemImage: "xmark") { tab?.stop() }
            } else {
                Button("Reload", systemImage: "arrow.clockwise") { tab?.reload() }
                    .disabled(tab?.url == nil)
            }
        }
        if let goHome {
            Button("Home", systemImage: "house", action: goHome)
                .accessibilityIdentifier("homeButton")
        }
    }
}
