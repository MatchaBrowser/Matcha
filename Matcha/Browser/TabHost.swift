import Foundation
import WebKit

/// Ce que le délégué de navigation (`NavigationCoordinator`) demande à qui possède les pages : les onglets d'un
/// Space et leur aperçu (`TabManager`), ou les mini-fenêtres (`MiniWindowManager`, tâche 4.5). Un seul délégué
/// pour toutes les pages : les tâches 5.5 (historique) et 5.8 (fenêtres de connexion) valent pour les deux.
@MainActor
protocol TabHost: AnyObject {
    var faviconService: FaviconService { get }
    /// Fenêtre à laquelle reviennent les téléchargements de ces pages (tâche 5.1).
    var downloadScope: DownloadScope { get }
    /// Onglet, ou page hors de la barre (aperçu, mini-fenêtre), qui possède `webView`.
    func page(for webView: WKWebView) -> BrowserTab?
    /// Vue web d'où part une navigation, pour `NavigationPolicy`.
    func navigationSource(of webView: WKWebView) -> NavigationSource
    /// Vrai si `webView` est celle d'un favori ou d'un épinglé (liens vers d'autres sites dans l'aperçu).
    func isFavoriteOrPinned(_ webView: WKWebView) -> Bool
    /// ⌘-clic, clic du milieu : `url` dans un onglet ; `configuration` est celle de la vue d'origine (même profil).
    func openLink(_ url: URL, configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool)
    /// `target=_blank`, `window.open` : une vue créée avec `configuration` telle quelle, sans quoi
    /// `window.opener` ne fonctionne pas ; nil refuse la fenêtre.
    func openWindow(configuration: WKWebViewConfiguration, from webView: WKWebView) -> WKWebView?
    /// Maj+clic : `url` dans l'aperçu ; faux si c'est refusé (le lien suit alors son cours).
    func openInPeek(_ url: URL, from webView: WKWebView, openingPoint: CGPoint) -> Bool
    /// La page a appelé `window.close()`.
    func closePage(of webView: WKWebView)
    /// Décisions de permission du profil de `webView` (tâche 5.2) ; nil : rien n'est retenu.
    func sitePermissions(for webView: WKWebView) -> SitePermissionScope?
    /// Zoom des pages par site (tâche 5.4) ; nil : les pages gardent leur zoom d'une page à l'autre.
    var siteZooms: SiteZoomStore? { get }
    /// Historique où retenir les visites de `webView` (tâche 5.5) ; nil : rien n'est retenu (fenêtre privée).
    func historyScope(for webView: WKWebView) -> HistoryScope?
    /// Vrai si `page` est à l'écran (tâche 5.7) : une page dont le processus s'arrête se recharge tout de suite si
    /// elle est visible, sinon quand on l'affiche.
    func isVisible(_ page: BrowserTab) -> Bool
}
