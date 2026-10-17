import AppKit

/// Choisir un onglet depuis la barre latérale ou la barre de commande : il est sélectionné et sa page
/// reçoit le clavier.
@MainActor
enum TabActivation {
    static func activate(_ tab: BrowserTab, in tabManager: TabManager) {
        let window = NSApp.keyWindow
        tabManager.select(tab)
        // Quitte le champ en cours d'édition (barre de commande, nom de dossier).
        window?.makeFirstResponder(nil)
        // La vue web de l'onglet n'est insérée dans la fenêtre qu'au prochain rendu.
        Task { @MainActor in
            if let webView = tab.webView {
                webView.window?.makeFirstResponder(webView)
            }
        }
    }

    /// Donne le clavier à la page de `tab` dès que sa vue web est dans une fenêtre (rendu suivant), sauf
    /// si quelqu'un l'a pris entre-temps (barre rouverte, champ de dossier…).
    static func focusPage(of tab: BrowserTab) {
        Task { @MainActor in
            for _ in 0 ..< 10 {
                if let webView = tab.webView, let window = webView.window {
                    if window.firstResponder === window {
                        window.makeFirstResponder(webView)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
