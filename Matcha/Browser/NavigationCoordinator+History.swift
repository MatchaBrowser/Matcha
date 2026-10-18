import WebKit

/// Historique (tâche 5.5) : la visite est retenue à la fin du chargement (`didFinish`, dans le fichier principal) ;
/// un chargement qui échoue n'en laisse aucune, et une adresse changée en attente d'être retenue est oubliée. Le
/// rechargement d'une page sortie de veille (tâche 5.6) ou dont le processus s'est arrêté (5.7) est aussi terminé. Le
/// bloqueur (tâche 6.2) revient à l'état de la page restée affichée.
extension NavigationCoordinator {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        navigationDidFail(in: webView)
        provisionalNavigationDidFail(in: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
        navigationDidFail(in: webView)
    }

    private func navigationDidFail(in webView: WKWebView) {
        guard let page = tabHost?.page(for: webView) else {
            return
        }
        page.history.navigationDidFail()
        page.suspension.endRestoring()
        page.crash.end()
    }
}
