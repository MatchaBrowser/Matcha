import WebKit

/// Historique (tâche 5.5) : la visite est retenue à la fin du chargement (`didFinish`, dans le fichier principal) ;
/// un chargement qui échoue n'en laisse aucune, et une adresse changée en attente d'être retenue est oubliée.
extension NavigationCoordinator {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: any Error) {
        tabHost?.page(for: webView)?.history.navigationDidFail()
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
        tabHost?.page(for: webView)?.history.navigationDidFail()
    }
}
