import WebKit

/// Menu contextuel des pages (tâche 5.9), côté délégué : la fenêtre que WebKit ouvre pour un élément de Matcha
/// (`BrowserWebView+PageMenu`) suit le choix retenu par la vue web d'origine, une seule fois et dans la seconde.
/// - « … dans un nouvel onglet » : un onglet en arrière-plan créé avec la configuration fournie par WebKit, après
///   l'onglet d'origine ; depuis l'aperçu, après son onglet d'origine, et l'aperçu reste un aperçu ; depuis une
///   mini-fenêtre, dans le Space visé (comme ⌘-clic) ; depuis une fenêtre de connexion, comme depuis sa page
///   d'origine (`TabHost.openWindow(configuration:from:inBackground:)`).
/// - « Ouvrir dans un aperçu » : `TabHost.openInPeek` (donc `TabManager.openPeek(_:from:openingPoint:)`) avec l'adresse
///   demandée, et WebKit n'a pas de fenêtre ; refusé (onglet qui n'est plus affiché, schéma about, blob, data,
///   javascript), un onglet en arrière-plan. La fenêtre du menu n'a pas de `window.opener` (vérifié) : rien à garder.
/// - Lien vers une autre app (mailto:…) : confié à cette app, comme ⌘-clic.
extension NavigationCoordinator: PageMenuDelegate {
    func pageMenuOffersPeek(in webView: WKWebView) -> Bool {
        tabHost?.navigationSource(of: webView) == .tab
    }

    /// Choix du menu contextuel de `webView` que cette fenêtre doit suivre, s'il y en a un ; il est alors oublié.
    /// Une fenêtre demandée par la page elle-même (lien `target=_blank`, formulaire, taille donnée, ou après
    /// l'échéance) ne le prend jamais.
    func takePageMenuIntent(
        of webView: WKWebView,
        for navigationAction: WKNavigationAction,
        features: PopupWindowFeatures,
    ) -> PageMenuIntent? {
        guard let webView = webView as? BrowserWebView else {
            return nil
        }
        let request = PageMenuWindowRequest(navigationType: navigationAction.navigationType, opensPopupWindow: features.opensPopupWindow)
        return webView.pageMenuIntent.take(for: request, at: now())
    }

    /// Vue de la fenêtre demandée pour `intent` ; nil si la page s'ouvre ailleurs (aperçu, autre app).
    func openWindow(
        for intent: PageMenuIntent,
        configuration: WKWebViewConfiguration,
        url: URL?,
        from webView: WKWebView,
        in tabHost: any TabHost,
    ) -> WKWebView? {
        if let url, !handles(url, in: webView) {
            open(externally: url)
            return nil
        }
        let point = intent.openingPoint
        if intent.destination == .peek, let url, Self.canOpenInPeek(url), tabHost.openInPeek(url, from: webView, openingPoint: point) {
            return nil
        }
        return tabHost.openWindow(configuration: configuration, from: webView, inBackground: true)
    }

    /// Les schémas que Maj+clic n'ouvre jamais dans l'aperçu (`NavigationPolicy`) n'y vont pas non plus par le menu.
    private static func canOpenInPeek(_ url: URL) -> Bool {
        !NavigationPolicy.schemesKeptInPlace.contains(url.scheme?.lowercased() ?? "")
    }
}
