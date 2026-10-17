import AppKit
import OSLog
import WebKit

/// Délégué de navigation et d'interface des vues web d'un `TabManager` : nouvelles fenêtres, fermeture par
/// la page, liens vers d'autres apps, clics avec modificateur, aperçu (Peek).
@MainActor
final class NavigationCoordinator: NSObject {
    weak var tabManager: TabManager?

    /// Confie une URL à l'app qui la gère ; remplaçable dans les tests.
    var openExternally: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    /// Réglage « liens des favoris et des épinglés vers d'autres sites dans l'aperçu », lu à chaque clic ;
    /// remplaçable dans les tests.
    var opensPinnedLinksInPeek: () -> Bool = { BrowserSettings.pinnedLinksOpenInPeek() }

    private func request(for navigationAction: WKNavigationAction, in webView: WKWebView) -> NavigationRequest {
        let url = navigationAction.request.url
        let source = navigationSource(of: webView)
        return NavigationRequest(
            url: url,
            navigationType: navigationAction.navigationType,
            modifierFlags: navigationAction.modifierFlags,
            buttonNumber: navigationAction.buttonNumber,
            targetsMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            isSchemeHandledByWebView: url.map { handles($0, in: webView) } ?? true,
            opensNewWindow: navigationAction.targetFrame == nil,
            pageURL: webView.url,
            shouldPerformDownload: navigationAction.shouldPerformDownload,
            source: source,
            opensOtherSitesInPeek: source == .tab && isFavoriteOrPinned(webView) && opensPinnedLinksInPeek(),
        )
    }

    /// Tâche 4.5 : les vues de la mini-fenêtre ne sont pas rangées ici (`.other`) : un Maj+clic y reste un clic.
    private func navigationSource(of webView: WKWebView) -> NavigationSource {
        guard let tabManager else {
            return .other
        }
        if tabManager.isPeek(webView) {
            return .peek
        }
        return tabManager.tab(for: webView) == nil ? .other : .tab
    }

    private func isFavoriteOrPinned(_ webView: WKWebView) -> Bool {
        guard let tabManager, let tab = tabManager.tab(for: webView), let place = tabManager.place(of: tab) else {
            return false
        }
        return place != .today
    }

    /// Point d'où l'aperçu grandit : le pointeur, en fractions de la vue web d'origine (origine en haut à gauche).
    private static func pointerPoint(in webView: WKWebView) -> CGPoint {
        guard let window = webView.window else {
            return PeekLayout.center
        }
        let point = webView.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return PeekLayout.fraction(of: point, in: webView.bounds.size, flipped: webView.isFlipped)
    }

    /// Vrai si WebKit charge lui-même ce schéma ou si la configuration de la vue lui associe un gestionnaire.
    private func handles(_ url: URL, in webView: WKWebView) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return true
        }
        return WKWebView.handlesURLScheme(scheme) || webView.configuration.urlSchemeHandler(forURLScheme: scheme) != nil
    }

    private func open(externally url: URL) {
        let scheme = url.scheme ?? "?"
        if openExternally(url) {
            Logger.browser.info("Lien \(scheme, privacy: .public): confié à une autre app")
        } else {
            Logger.browser.notice("Aucune app ne gère les liens \(scheme, privacy: .public):")
        }
    }

    /// Lien à ouvrir dans l'aperçu : refusé (le lien suit son cours) si sa vue web n'est pas affichée.
    private func openInPeek(_ url: URL, from webView: WKWebView, decisionHandler: @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let tabManager, let source = tabManager.tabOrPeek(for: webView), tabManager.canPeek(from: source) else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        tabManager.openPeek(url, from: source, openingPoint: Self.pointerPoint(in: webView))
    }
}

extension NavigationCoordinator: WKNavigationDelegate {
    /// Nouvelle page affichée (onglet ou aperçu) : icône connue de son domaine, ou pastille en attendant mieux.
    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        guard let tabManager, let tab = tabManager.tabOrPeek(for: webView) else {
            return
        }
        tab.favicon = webView.url?.host().flatMap(tabManager.faviconService.cachedIcon(forHost:))
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        guard let tabManager, let tab = tabManager.tabOrPeek(for: webView) else {
            return
        }
        tabManager.faviconService.refreshIcon(of: tab)
        // Retenu à chaque page chargée : un plantage ne fait pas perdre l'historique.
        tab.captureInteractionState()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void,
    ) {
        switch NavigationPolicy.decide(request(for: navigationAction, in: webView)) {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case let .openExternally(url):
            decisionHandler(.cancel)
            open(externally: url)
        case let .openInNewTab(url, inBackground):
            decisionHandler(.cancel)
            guard let tabManager else {
                return
            }
            // Même configuration que la vue d'origine : même profil. Depuis l'aperçu, après son onglet d'origine.
            let anchor = tabManager.insertionAnchor(for: webView)
            tabManager.insertTab(configuration: webView.configuration, after: anchor, select: !inBackground).load(url)
        case let .openInPeek(url):
            openInPeek(url, from: webView, decisionHandler: decisionHandler)
        }
    }
}

extension NavigationCoordinator: WKUIDelegate {
    /// Lien `target=_blank` ou `window.open` : la nouvelle vue doit être créée avec la configuration
    /// fournie, sans quoi `window.opener` ne fonctionne pas. WebKit y charge ensuite la requête.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for _: WKNavigationAction,
        windowFeatures _: WKWindowFeatures,
    ) -> WKWebView? {
        guard let tabManager else {
            return nil
        }
        // Fenêtre ouverte par l'aperçu : il devient d'abord un onglet, pour que `window.opener` reste valable.
        // Tâche 5.8 : une fenêtre de connexion (taille donnée) ira dans sa propre fenêtre, sans `openPeekAsTab`.
        let opener = tabManager.tab(for: webView) ?? (tabManager.isPeek(webView) ? tabManager.openPeekAsTab() : nil)
        return tabManager.insertTab(configuration: configuration, after: opener, select: true).makeWebViewIfNeeded()
    }

    /// La page a appelé `window.close()`.
    func webViewDidClose(_ webView: WKWebView) {
        guard let tabManager else {
            return
        }
        if tabManager.isPeek(webView) {
            PeekActions.close(in: tabManager)
        } else if let tab = tabManager.tab(for: webView) {
            tabManager.close(tab)
        }
    }
}
