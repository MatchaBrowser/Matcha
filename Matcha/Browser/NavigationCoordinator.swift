import AppKit
import OSLog
import WebKit

/// Délégué de navigation et d'interface des vues web d'un `TabManager` :
/// nouvelles fenêtres, fermeture par la page, liens vers d'autres apps, clics avec modificateur.
@MainActor
final class NavigationCoordinator: NSObject {
    weak var tabManager: TabManager?

    /// Confie une URL à l'app qui la gère ; remplaçable dans les tests.
    var openExternally: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    private func request(for navigationAction: WKNavigationAction, in webView: WKWebView) -> NavigationRequest {
        let url = navigationAction.request.url
        return NavigationRequest(
            url: url,
            navigationType: navigationAction.navigationType,
            modifierFlags: navigationAction.modifierFlags,
            buttonNumber: navigationAction.buttonNumber,
            targetsMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            isSchemeHandledByWebView: url.map { handles($0, in: webView) } ?? true,
        )
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
}

extension NavigationCoordinator: WKNavigationDelegate {
    /// Nouvelle page affichée : icône connue de son domaine, ou pastille en attendant mieux.
    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        guard let tabManager, let tab = tabManager.tab(for: webView) else {
            return
        }
        tab.favicon = webView.url?.host().flatMap(tabManager.faviconService.cachedIcon(forHost:))
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        guard let tabManager, let tab = tabManager.tab(for: webView) else {
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
            // Même configuration que la vue d'origine : même profil, mêmes réglages.
            let opener = tabManager.tab(for: webView)
            tabManager.insertTab(configuration: webView.configuration, after: opener, select: !inBackground).load(url)
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
        let opener = tabManager.tab(for: webView)
        return tabManager.insertTab(configuration: configuration, after: opener, select: true).makeWebViewIfNeeded()
    }

    /// La page a appelé `window.close()`.
    func webViewDidClose(_ webView: WKWebView) {
        guard let tabManager, let tab = tabManager.tab(for: webView) else {
            return
        }
        tabManager.close(tab)
    }
}
