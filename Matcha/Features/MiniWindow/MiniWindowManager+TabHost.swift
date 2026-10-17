import Foundation
import OSLog
import WebKit

/// Les pages des mini-fenêtres vues par le délégué de navigation (`NavigationCoordinator`) :
/// - `target=_blank` et `window.open` : une nouvelle mini-fenêtre, créée avec la configuration fournie par
///   WebKit (`window.opener` reste valable), même profil ;
/// - ⌘-clic, clic du milieu, ⇧⌘-clic : un onglet en arrière-plan dans le Space visé, la fenêtre principale ne
///   passe pas devant ; sans Space de ce profil, une nouvelle mini-fenêtre (jamais les cookies d'un autre profil) ;
/// - `window.close()` : la mini-fenêtre se ferme ;
/// - pas d'aperçu : un Maj+clic reste un clic (`NavigationSource.other`) ;
/// - téléchargements : dans la liste de la fenêtre principale.
/// Tâche 5.8 : `windowFeatures` (fenêtres de connexion) est encore ignoré.
extension MiniWindowManager: TabHost {
    var faviconService: FaviconService {
        session.faviconService
    }

    /// Les mini-fenêtres n'ont pas de barre latérale : leurs téléchargements vont dans la liste de la fenêtre
    /// principale.
    var downloadScope: DownloadScope {
        .regular
    }

    func page(for webView: WKWebView) -> BrowserTab? {
        window(for: webView)?.tab
    }

    func navigationSource(of _: WKWebView) -> NavigationSource {
        .other
    }

    func isFavoriteOrPinned(_: WKWebView) -> Bool {
        false
    }

    func openLink(_ url: URL, configuration: WKWebViewConfiguration, from webView: WKWebView, inBackground _: Bool) {
        let opener = window(for: webView)
        let profileID = opener?.profileID ?? displayedSpace.record.profile?.id
        let space = defaultTarget(profileID: profileID)
        guard space.record.profile?.id == profileID else {
            // Plus aucun Space de ce profil : la page s'ouvre à côté, dans une mini-fenêtre du même profil.
            let controller = show(BrowserTab(configuration: configuration, openerID: opener?.tab.id), profileID: profileID)
            controller.tab.load(url)
            controller.showWebView()
            Logger.miniWindow.info("Mini-fenêtre ouverte (\(Source.link.rawValue, privacy: .public))")
            return
        }
        space.tabManager.newTab(url: url, select: false)
        Logger.miniWindow.info("Lien d'une mini-fenêtre ouvert en arrière-plan dans un Space")
    }

    func openWindow(configuration: WKWebViewConfiguration, from webView: WKWebView) -> WKWebView? {
        let opener = window(for: webView)
        let profileID = opener?.profileID ?? displayedSpace.record.profile?.id
        let controller = show(BrowserTab(configuration: configuration, openerID: opener?.tab.id), profileID: profileID)
        let newWebView = controller.tab.makeWebViewIfNeeded()
        controller.showWebView()
        Logger.miniWindow.info("Mini-fenêtre ouverte (\(Source.page.rawValue, privacy: .public))")
        return newWebView
    }

    /// Pas d'aperçu dans une mini-fenêtre (jamais demandé) : refusé, le lien suit son cours sur place.
    func openInPeek(_: URL, from _: WKWebView, openingPoint _: CGPoint) -> Bool {
        false
    }

    func closePage(of webView: WKWebView) {
        window(for: webView)?.close()
    }
}
