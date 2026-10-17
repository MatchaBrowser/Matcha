import AppKit
import OSLog
import WebKit

/// Délégué de navigation et d'interface des vues web d'un `TabHost` (les onglets d'un Space et leur aperçu, ou
/// les mini-fenêtres) : nouvelles fenêtres, fermeture par la page, liens vers d'autres apps, clics avec
/// modificateur, aperçu (Peek), téléchargements, permissions des sites (`+Permissions`). Les règles viennent de
/// `NavigationPolicy`, `DownloadPolicy` et `SitePermissionPolicy` ; l'hôte décide où vont les pages.
@MainActor
final class NavigationCoordinator: NSObject {
    weak var tabHost: (any TabHost)?
    /// Reçoit les téléchargements ; remplacé dans les tests (dossier temporaire).
    var downloadManager = DownloadManager.shared

    /// Confie une URL à l'app qui la gère ; remplaçable dans les tests.
    var openExternally: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    /// Réglage « liens des favoris et des épinglés vers d'autres sites dans l'aperçu », lu à chaque clic ;
    /// remplaçable dans les tests.
    var opensPinnedLinksInPeek: () -> Bool = { BrowserSettings.pinnedLinksOpenInPeek() }

    private func request(for navigationAction: WKNavigationAction, in webView: WKWebView) -> NavigationRequest {
        let url = navigationAction.request.url
        // Sans hôte, la page n'est rangée nulle part : un Maj+clic y reste un clic.
        let source = tabHost?.navigationSource(of: webView) ?? .other
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
            opensOtherSitesInPeek: source == .tab && tabHost?.isFavoriteOrPinned(webView) == true && opensPinnedLinksInPeek(),
        )
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

    /// Confie à `downloadManager` un téléchargement que WebKit vient de créer. La page d'origine est le référent de
    /// la requête, sinon la page affichée (jamais l'adresse en cours de chargement, qui est celle du fichier).
    private func track(_ download: WKDownload, from webView: WKWebView) {
        let referrer = download.originalRequest?.value(forHTTPHeaderField: "Referer").flatMap(URL.init(string:))
        downloadManager.track(
            download,
            scope: tabHost?.downloadScope ?? .regular,
            pageURL: referrer ?? webView.backForwardList.currentItem?.url,
        )
    }

    /// Lien à ouvrir dans l'aperçu : refusé (le lien suit son cours) si l'hôte ne peut pas l'ouvrir.
    private func openInPeek(_ url: URL, from webView: WKWebView, decisionHandler: @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let tabHost, tabHost.openInPeek(url, from: webView, openingPoint: Self.pointerPoint(in: webView)) else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
    }
}

extension NavigationCoordinator: WKNavigationDelegate {
    /// Nouvelle page affichée (onglet, aperçu ou mini-fenêtre) : icône connue de son domaine, ou pastille en
    /// attendant mieux. Les demandes de permission de l'ancienne page n'ont plus d'objet : refusées.
    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        guard let tabHost, let tab = tabHost.page(for: webView) else {
            return
        }
        tab.permissionPrompts.denyAll()
        tab.favicon = webView.url?.host().flatMap(tabHost.faviconService.cachedIcon(forHost:))
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        guard let tabHost, let tab = tabHost.page(for: webView) else {
            return
        }
        tabHost.faviconService.refreshIcon(of: tab)
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
            // Même configuration que la vue d'origine : même profil.
            tabHost?.openLink(url, configuration: webView.configuration, from: webView, inBackground: inBackground)
        case let .openInPeek(url):
            openInPeek(url, from: webView, decisionHandler: decisionHandler)
        case .download:
            decisionHandler(.download)
        }
    }

    /// Une réponse que WebKit ne sait pas afficher, ou une pièce jointe, devient un téléchargement.
    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void,
    ) {
        let response = DownloadResponse(navigationResponse.response, canShowMIMEType: navigationResponse.canShowMIMEType)
        decisionHandler(DownloadPolicy.shouldDownload(response) ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction _: WKNavigationAction, didBecome download: WKDownload) {
        track(download, from: webView)
    }

    func webView(_ webView: WKWebView, navigationResponse _: WKNavigationResponse, didBecome download: WKDownload) {
        track(download, from: webView)
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
        tabHost?.openWindow(configuration: configuration, from: webView)
    }

    /// La page a appelé `window.close()`.
    func webViewDidClose(_ webView: WKWebView) {
        tabHost?.closePage(of: webView)
    }
}
