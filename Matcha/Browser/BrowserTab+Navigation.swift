import Foundation
import WebKit

/// Titre affiché et commandes de navigation de la page (boutons, menus, raccourcis).
extension BrowserTab {
    /// Titre à afficher : titre de la page, sinon hôte, sinon « Nouvel onglet ».
    var displayTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        if let host = url?.host(), !host.isEmpty {
            return host
        }
        return url?.absoluteString ?? String(localized: "New Tab")
    }

    /// Les commandes de navigation mènent ailleurs que la page sortie de veille : plus de capture par-dessus ; une page
    /// plantée (tâche 5.7) quitte son message.
    func goBack() {
        suspension.endRestoring()
        crash.pageWillNavigate()
        webView?.goBack()
    }

    func goForward() {
        suspension.endRestoring()
        crash.pageWillNavigate()
        webView?.goForward()
    }

    /// Après un arrêt du processus (tâche 5.7 : rechargement automatique, bouton du message, ⌘R), le rechargement
    /// n'est pas une nouvelle visite de l'historique, comme la sortie de veille ; une page arrêtée avant d'avoir rien
    /// affiché (rien à recharger) charge son adresse.
    func reload() {
        suspension.endRestoring()
        guard crash.isRecovering else {
            webView?.reload()
            return
        }
        crash.pageWillNavigate()
        history.pageWillResume(url: url)
        if webView?.reload() == nil, let url {
            load(url)
        }
    }

    func stop() {
        webView?.stopLoading()
    }
}
