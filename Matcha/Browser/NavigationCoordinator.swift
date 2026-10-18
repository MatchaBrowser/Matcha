import AppKit
import OSLog
import WebKit

/// Délégué de navigation et d'interface des vues web d'un `TabHost` (les onglets d'un Space et leur aperçu, les
/// mini-fenêtres ou les fenêtres de connexion) : nouvelles fenêtres, fenêtres de connexion (`PopupWindowManager`),
/// fermeture par la page, liens vers d'autres apps, clics avec modificateur, aperçu (Peek), téléchargements,
/// permissions des sites (`+Permissions`), historique (`+History`), arrêt du processus d'une page (`+Crash`), menu
/// contextuel des pages (`+PageMenu`). Les règles viennent de `NavigationPolicy`, `PopupWindowFeatures`,
/// `DownloadPolicy`, `SitePermissionPolicy`, `PageCrashPolicy` et `PendingPageMenuIntent` ; l'hôte décide où vont les
/// pages.
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
    /// Heure des arrêts du processus des pages (tâche 5.7) ; remplacée dans les tests.
    var now: () -> Date = { .now }

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

    /// Vrai si WebKit charge lui-même ce schéma ou si la configuration de la vue lui associe un gestionnaire.
    func handles(_ url: URL, in webView: WKWebView) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return true
        }
        return WKWebView.handlesURLScheme(scheme) || webView.configuration.urlSchemeHandler(forURLScheme: scheme) != nil
    }

    func open(externally url: URL) {
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
        tabHost?.downloadDidStart(in: webView)
    }

    /// Lien à ouvrir dans l'aperçu : refusé (le lien suit son cours) si l'hôte ne peut pas l'ouvrir.
    private func openInPeek(_ url: URL, from webView: WKWebView, decisionHandler: @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let tabHost, tabHost.openInPeek(url, from: webView, openingPoint: webView.pointerPeekPoint) else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
    }
}

extension NavigationCoordinator: WKNavigationDelegate {
    /// Nouvelle page affichée (onglet, aperçu ou mini-fenêtre) : icône connue de son domaine, ou pastille en
    /// attendant mieux, et zoom de son site (tâche 5.4). Les demandes de permission de l'ancienne page n'ont plus
    /// d'objet : refusées.
    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        guard let tabHost, let tab = tabHost.page(for: webView) else {
            return
        }
        tab.permissionPrompts.denyAll()
        tab.favicon = webView.url?.host().flatMap(tabHost.faviconService.cachedIcon(forHost:))
        tabHost.siteZooms?.pageDidCommit(tab, url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        guard let tabHost, let tab = tabHost.page(for: webView) else {
            return
        }
        // Page sortie de veille rechargée (tâche 5.6) : sa capture laisse la place à la page ; page rechargée après un
        // arrêt de son processus (5.7) : l'onglet suit de nouveau sa vue web.
        tab.suspension.endRestoring()
        tab.crash.end()
        tabHost.faviconService.refreshIcon(of: tab)
        // Retenu à chaque page chargée : un plantage ne fait pas perdre l'historique.
        tab.captureInteractionState()
        // Visite retenue dans l'historique du profil (tâche 5.5), jamais pour une fenêtre privée.
        tab.history.pageDidFinishLoading(url: webView.url, title: webView.title, scope: tabHost.historyScope(for: webView))
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
    /// fournie, sans quoi `window.opener` ne fonctionne pas. WebKit y charge ensuite la requête. Une fenêtre dont la
    /// page donne la taille (connexion Google, Apple, banque) s'ouvre dans sa propre petite fenêtre (tâche 5.8), même
    /// depuis un aperçu (qui reste un aperçu) ou une mini-fenêtre ; sinon, l'hôte en fait un onglet (ou une
    /// mini-fenêtre). Une fenêtre ouverte pour un choix du menu contextuel (tâche 5.9) suit ce choix (`+PageMenu`).
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
    ) -> WKWebView? {
        guard let tabHost else {
            return nil
        }
        let features = PopupWindowFeatures(windowFeatures)
        if let intent = takePageMenuIntent(of: webView, for: navigationAction, features: features) {
            return openWindow(for: intent, configuration: configuration, url: navigationAction.request.url, from: webView, in: tabHost)
        }
        guard features.opensPopupWindow, let popupWindows = tabHost.popupWindows else {
            return tabHost.openWindow(configuration: configuration, from: webView, inBackground: false)
        }
        // Jamais l'adresse : l'hôte seulement.
        let host = navigationAction.request.url?.host() ?? "?"
        Logger.browser.info("Fenêtre de connexion ouverte (\(host, privacy: .private))")
        return popupWindows.open(configuration: configuration, features: features, opener: PopupOpener(host: tabHost, webView: webView))
    }

    /// La page a appelé `window.close()`.
    func webViewDidClose(_ webView: WKWebView) {
        tabHost?.closePage(of: webView)
    }
}
