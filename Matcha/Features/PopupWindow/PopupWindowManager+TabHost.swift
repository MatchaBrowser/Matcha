import Foundation
import WebKit

/// Les pages des fenêtres de connexion vues par le délégué de navigation (`NavigationCoordinator`) :
/// - permissions des sites et historique : ceux de la page d'origine (son profil ; rien en fenêtre privée) ;
/// - téléchargements : dans la liste de la session ; une fenêtre qui n'a rien affiché avant de télécharger se ferme ;
/// - ⌘-clic, clic du milieu, `target=_blank`, `window.open` sans taille, « … dans un nouvel onglet » du menu
///   contextuel (tâche 5.9) : comme depuis la page d'origine (onglet de sa fenêtre, ou mini-fenêtre), tant qu'elle
///   est ouverte ; sinon une autre fenêtre de connexion, du même profil ;
/// - `window.open` avec une taille : une autre fenêtre de connexion, au-dessus de celle-ci (`NavigationCoordinator`) ;
/// - pas d'aperçu : un Maj+clic reste un clic (`NavigationSource.other`), pas de « Ouvrir dans un aperçu » ;
/// - `window.close()` : la fenêtre se ferme ;
/// - processus de la page arrêté (tâche 5.7) : la page est visible tant que sa fenêtre est ouverte, elle se recharge.
extension PopupWindowManager: TabHost {
    func page(for webView: WKWebView) -> BrowserTab? {
        window(for: webView)?.tab
    }

    func navigationSource(of _: WKWebView) -> NavigationSource {
        .other
    }

    func isFavoriteOrPinned(_: WKWebView) -> Bool {
        false
    }

    func openLink(_ url: URL, configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) {
        guard let controller = window(for: webView) else {
            return
        }
        if let source = controller.opener.liveSource {
            source.host.openLink(url, configuration: configuration, from: source.webView, inBackground: inBackground)
            return
        }
        let tab = BrowserTab(configuration: configuration, openerID: controller.tab.id)
        show(tab, features: PopupWindowFeatures(), opener: PopupOpener(host: self, webView: webView)).tab.load(url)
    }

    func openWindow(configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground: Bool) -> WKWebView? {
        guard let controller = window(for: webView) else {
            return nil
        }
        if let source = controller.opener.liveSource {
            return source.host.openWindow(configuration: configuration, from: source.webView, inBackground: inBackground)
        }
        return open(configuration: configuration, features: PopupWindowFeatures(), opener: PopupOpener(host: self, webView: webView))
    }

    /// Pas d'aperçu dans une fenêtre de connexion : refusé, le lien suit son cours sur place.
    func openInPeek(_: URL, from _: WKWebView, openingPoint _: CGPoint) -> Bool {
        false
    }

    func closePage(of webView: WKWebView) {
        window(for: webView)?.close()
    }

    /// Une fenêtre qui ne fait que télécharger (aucune page affichée avant) resterait vide : elle se ferme, comme dans
    /// Safari, au tour suivant de la boucle principale (WebKit finit d'abord de prévenir le délégué). Le téléchargement
    /// continue : il survit à la vue web qui l'a lancé (vérifié en 5.6, et par les tests).
    func downloadDidStart(in webView: WKWebView) {
        guard let controller = window(for: webView), webView.backForwardList.currentItem == nil else {
            return
        }
        Task { [weak controller] in
            controller?.close()
        }
    }

    func sitePermissions(for webView: WKWebView) -> SitePermissionScope? {
        window(for: webView)?.opener.sitePermissions
    }

    func historyScope(for webView: WKWebView) -> HistoryScope? {
        window(for: webView)?.opener.history
    }

    /// Fenêtre ouverte, même au second plan (comme une mini-fenêtre).
    func isVisible(_ page: BrowserTab) -> Bool {
        window(for: page) != nil
    }

    /// Une fenêtre de connexion qui en ouvre une autre en donnant sa taille : une de plus, au-dessus d'elle.
    var popupWindows: PopupWindowManager? {
        self
    }
}
