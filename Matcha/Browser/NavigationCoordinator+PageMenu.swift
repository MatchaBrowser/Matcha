import WebKit

/// Context menu of pages (task 5.9), delegate side: the window WebKit opens for a Matcha item
/// (`BrowserWebView+PageMenu`) follows the choice recorded by the originating web view, only once and within a second.
/// - “… in New Tab”: a background tab created with the configuration supplied by WebKit, after the originating tab;
///   from Peek, after its originating tab, and Peek stays Peek; from a mini window, in the target Space (like
///   ⌘-click); from a sign-in window, as from its originating page
///   (`TabHost.openWindow(configuration:from:inBackground:)`).
/// - “Open Link in Peek”: `TabHost.openInPeek` (hence `TabManager.openPeek(_:from:openingPoint:)`) with the requested
///   address, and WebKit gets no window; if refused (tab no longer displayed, a link the app doesn't open itself:
///   `NavigationPolicy.opensElsewhere`), a background tab. The menu's window has no `window.opener` (checked): nothing to keep.
/// - Link to another app (mailto:…): handed to that app, like ⌘-click.
extension NavigationCoordinator: PageMenuDelegate {
    func pageMenuOffersPeek(in webView: WKWebView) -> Bool {
        tabHost?.navigationSource(of: webView) == .tab
    }

    /// Save As… and Print…: on the page of `webView`; View Page Source: in a new foreground tab, after it (like a link
    /// opened in a new tab), same profile.
    func pageMenu(perform command: PageCommand, in webView: WKWebView) {
        guard let tabHost, let page = tabHost.page(for: webView) else {
            return
        }
        switch command {
        case .saveAs:
            dialogs.save(page)
        case .print:
            dialogs.print(page)
        case .viewSource:
            if let viewer = PageSource.viewerURL(for: page.url) {
                PageSourceSchemeHandler.of(webView.configuration)?.authorize(viewer, in: webView.configuration.websiteDataStore)
                tabHost.openLink(viewer, configuration: webView.configuration, from: webView, inBackground: false)
            }
        case .goBack, .goForward:
            break
        }
    }

    /// Context menu choice of `webView` that this window must follow, if there is one; it is then forgotten.
    /// A window requested by the page itself (`target=_blank` link, form, given size, or after the deadline) never
    /// takes it.
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

    /// View of the window requested for `intent`; nil if the page opens elsewhere (Peek, another app).
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
        let opensInPeek = intent.destination == .peek && url.map { NavigationPolicy.opensElsewhere($0, from: webView.url) } == true
        if opensInPeek, let url, tabHost.openInPeek(url, from: webView, openingPoint: intent.openingPoint) {
            return nil
        }
        return tabHost.openWindow(configuration: configuration, from: webView, inBackground: true)
    }
}
