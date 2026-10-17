import Foundation
import WebKit

/// Les pages d'un Space vues par le délégué de navigation : onglets rangés et aperçu (tâche 4.4).
extension TabManager: TabHost {
    func page(for webView: WKWebView) -> BrowserTab? {
        tabOrPeek(for: webView)
    }

    func navigationSource(of webView: WKWebView) -> NavigationSource {
        if isPeek(webView) {
            return .peek
        }
        return tab(for: webView) == nil ? .other : .tab
    }

    func isFavoriteOrPinned(_ webView: WKWebView) -> Bool {
        guard let tab = tab(for: webView), let place = place(of: tab) else {
            return false
        }
        return place != .today
    }

    /// Après l'onglet d'origine ; depuis l'aperçu, après son onglet d'origine.
    func openLink(_ url: URL, configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) {
        insertTab(configuration: configuration, after: insertionAnchor(for: webView), select: !inBackground).load(url)
    }

    /// Fenêtre ouverte par l'aperçu : il devient d'abord un onglet, pour que `window.opener` reste valable.
    /// Tâche 5.8 : une fenêtre de connexion (taille donnée) ira dans sa propre fenêtre, sans `openPeekAsTab`.
    func openWindow(configuration: WKWebViewConfiguration, from webView: WKWebView) -> WKWebView? {
        let opener = tab(for: webView) ?? (isPeek(webView) ? openPeekAsTab() : nil)
        return insertTab(configuration: configuration, after: opener, select: true).makeWebViewIfNeeded()
    }

    /// Refusé si la vue web d'origine n'est pas affichée.
    func openInPeek(_ url: URL, from webView: WKWebView, openingPoint: CGPoint) -> Bool {
        guard let source = tabOrPeek(for: webView), canPeek(from: source) else {
            return false
        }
        openPeek(url, from: source, openingPoint: openingPoint)
        return true
    }

    /// Onglets et aperçu partagent le profil du Space.
    func sitePermissions(for _: WKWebView) -> SitePermissionScope? {
        sitePermissions
    }

    /// Onglets et aperçu : le profil et le Space de ce Space.
    func historyScope(for _: WKWebView) -> HistoryScope? {
        history
    }

    func closePage(of webView: WKWebView) {
        if isPeek(webView) {
            PeekActions.close(in: self)
        } else if let tab = tab(for: webView) {
            close(tab)
        }
    }
}
