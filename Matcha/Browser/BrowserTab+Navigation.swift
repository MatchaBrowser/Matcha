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

    /// Les commandes de navigation mènent ailleurs que la page sortie de veille : plus de capture par-dessus.
    func goBack() {
        suspension.endRestoring()
        webView?.goBack()
    }

    func goForward() {
        suspension.endRestoring()
        webView?.goForward()
    }

    func reload() {
        suspension.endRestoring()
        webView?.reload()
    }

    func stop() {
        webView?.stopLoading()
    }
}
