import AppKit
import OSLog
import WebKit

/// Navigation and UI delegate of the web views of a `TabHost` (the tabs of a Space and their Peek, the mini windows
/// or the sign-in windows): new windows, sign-in windows (`PopupWindowManager`), closing by the page, links to other
/// apps (`+ExternalApps`), clicks with modifiers, Peek, downloads, site permissions (`+Permissions`), history (`+History`),
/// termination of a page's process (`+Crash`), context menu of pages (`+PageMenu`), blocker (task 6.2). The rules
/// come from `NavigationPolicy`, `PopupWindowFeatures`, `DownloadPolicy`, `SitePermissionPolicy`, `PageCrashPolicy`
/// and `PendingPageMenuIntent`; the host decides where pages go.
@MainActor
final class NavigationCoordinator: NSObject {
    weak var tabHost: (any TabHost)?
    /// Receives the downloads (the app's, given by its host); nil: pages can't download.
    var downloadManager: DownloadManager?
    /// Shows the notifications of the pages (`+Notifications`); nil: they read “denied”.
    var notificationCenter: PageNotificationCenter?

    /// Hands a URL to the app that handles it; replaceable in tests.
    var openExternally: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    /// App that opens a link (`+ExternalApps`); replaceable in tests.
    var applicationForURL: (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    /// JavaScript dialogs, files to send, logins, saving and printing (`+Dialogs`, `+Authentication`, `+PageMenu`): the
    /// app's, given by its host; replaced in tests.
    var dialogs: any PageDialogPresenting = UnavailablePageDialogs()
    /// “Open links to other websites from Favorites and pinned tabs in Peek” setting, read at each click;
    /// replaceable in tests.
    var opensPinnedLinksInPeek: () -> Bool = { BrowserSettings.pinnedLinksOpenInPeek() }
    /// Time of page process terminations (task 5.7); replaced in tests.
    var now: () -> Date = { .now }

    private func request(for navigationAction: WKNavigationAction, in webView: WKWebView) -> NavigationRequest {
        let url = navigationAction.request.url
        // Without a host, the page is placed nowhere: a Shift-click stays a click there.
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

    /// True if WebKit loads this scheme itself or if the view's configuration associates a handler with it. Extension
    /// pages (`webkit-extension:`, task 6.3) are served by WebKit without a visible handler: never handed to another
    /// app (WebKit itself refuses to load them in a view that is not their extension's).
    func handles(_ url: URL, in webView: WKWebView) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return true
        }
        return WKWebView.handlesURLScheme(scheme) || webView.configuration.urlSchemeHandler(forURLScheme: scheme) != nil
            || scheme == ExtensionManager.scheme
    }

    func open(externally url: URL) {
        let scheme = url.scheme ?? "?"
        if openExternally(url) {
            Logger.browser.info("\(scheme, privacy: .public): link handed to another app")
        } else {
            Logger.browser.notice("No app handles \(scheme, privacy: .public): links")
        }
    }

    /// Hands to `downloadManager` a download WebKit has just created. The originating page is the request's referrer,
    /// otherwise the displayed page (never the address being loaded, which is the file's).
    private func track(_ download: WKDownload, from webView: WKWebView) {
        guard let downloadManager else {
            download.cancel(nil)
            return
        }
        let referrer = download.originalRequest?.value(forHTTPHeaderField: "Referer").flatMap(URL.init(string:))
        downloadManager.track(
            download,
            scope: tabHost?.downloadScope ?? .regular,
            pageURL: referrer ?? webView.backForwardList.currentItem?.url,
        )
        tabHost?.downloadDidStart(in: webView)
    }

    /// Link to open in Peek; false if the host cannot open it (the link then proceeds as usual).
    private func openInPeek(_ url: URL, from webView: WKWebView) -> Bool {
        tabHost?.openInPeek(url, from: webView, openingPoint: webView.pointerPeekPoint) == true
    }

    /// Navigation allowed. Blocker (task 6.2): for the main document, the page's lists are set first, or removed if
    /// the destination site is an exception; they thus apply from this very load (checked).
    private func allow(
        _ navigationAction: WKNavigationAction,
        in webView: WKWebView,
        decisionHandler: @MainActor @Sendable (WKNavigationActionPolicy) -> Void,
    ) {
        if navigationAction.targetFrame?.isMainFrame == true {
            tabHost?.contentBlocking?.prepare(webView, for: navigationAction.request.url)
            prepareNotifications(for: webView)
        }
        decisionHandler(.allow)
    }

    /// Blocker (task 6.2): an allowed navigation that does not complete (network error, response turned into a
    /// download) leaves the displayed page, whose lists return to the state of its document. Except on cancellation:
    /// most often another navigation, already prepared, is replacing it.
    func provisionalNavigationDidFail(in webView: WKWebView, error: any Error) {
        let error = error as NSError
        guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else {
            return
        }
        tabHost?.contentBlocking?.prepare(webView, for: webView.backForwardList.currentItem?.url)
    }
}

extension NavigationCoordinator: WKNavigationDelegate {
    /// New page displayed (tab, Peek or mini window): known icon of its domain, or a placeholder badge until something
    /// better comes, and zoom of its site (task 5.4). The permission requests of the old page no longer apply: refused;
    /// its sound stopped with it (task 5.10).
    func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
        guard let tabHost, let tab = tabHost.page(for: webView) else {
            return
        }
        // Blocker (task 6.2): realigned on the displayed document (redirect, back from the cache).
        tabHost.contentBlocking?.prepare(webView, for: webView.url)
        tab.documentDidChange()
        tab.permissionPrompts.denyAll()
        tab.pageDownloads.documentDidChange()
        tab.pageDialogs.documentDidChange()
        tab.audio.reset()
        notificationsDocumentDidChange(in: webView, page: tab)
        tabHost.faviconService.showCachedIcon(on: tab, host: webView.url?.host())
        tabHost.siteZooms?.pageDidCommit(tab, url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        guard let tabHost, let tab = tabHost.page(for: webView) else {
            return
        }
        // Page woken from sleep reloaded (task 5.6): its snapshot gives way to the page; page reloaded after its
        // process stopped (5.7): the tab follows its web view again.
        tab.suspension.endRestoring()
        tab.crash.end()
        tab.documentDidChange()
        tabHost.faviconService.refreshIcon(of: tab)
        // Recorded at each loaded page: a crash does not lose the history.
        tab.captureInteractionState()
        // Visit recorded in the profile's history (task 5.5), never for a private window.
        tab.history.pageDidFinishLoading(url: webView.url, title: webView.title, scope: tabHost.historyScope(for: webView))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void,
    ) {
        recordClick(navigationAction, in: webView)
        switch NavigationPolicy.decide(request(for: navigationAction, in: webView)) {
        case .allow:
            allow(navigationAction, in: webView, decisionHandler: decisionHandler)
        case .cancel:
            decisionHandler(.cancel)
        case let .openExternally(url):
            decisionHandler(.cancel)
            requestOpening(url, from: webView)
        case let .openInNewTab(url, inBackground):
            decisionHandler(.cancel)
            // Same configuration as the originating view: same profile.
            tabHost?.openLink(url, configuration: webView.configuration, from: webView, inBackground: inBackground)
        case let .openInPeek(url):
            if openInPeek(url, from: webView) {
                decisionHandler(.cancel)
            } else {
                allow(navigationAction, in: webView, decisionHandler: decisionHandler)
            }
        case .download:
            let isSubframe = navigationAction.targetFrame?.isMainFrame == false
            startDownload(in: webView, isSubframe: isSubframe) { decisionHandler($0 ? .download : .cancel) }
        }
    }

    /// A response WebKit cannot display, or an attachment, becomes a download (if the page may download it: `+Downloads`).
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void,
    ) {
        let response = DownloadResponse(navigationResponse.response, canShowMIMEType: navigationResponse.canShowMIMEType)
        guard DownloadPolicy.shouldDownload(response) else {
            decisionHandler(.allow)
            return
        }
        startDownload(in: webView, isSubframe: !navigationResponse.isForMainFrame) { decisionHandler($0 ? .download : .cancel) }
    }

    func webView(_ webView: WKWebView, navigationAction _: WKNavigationAction, didBecome download: WKDownload) {
        track(download, from: webView)
    }

    func webView(_ webView: WKWebView, navigationResponse _: WKNavigationResponse, didBecome download: WKDownload) {
        track(download, from: webView)
    }
}

extension NavigationCoordinator: WKUIDelegate {
    /// `target=_blank` link or `window.open`: the new view must be created with the supplied configuration, otherwise
    /// `window.opener` does not work. WebKit then loads the request in it. A window whose page gives its size (Google,
    /// Apple or bank sign-in) opens in its own small window (task 5.8), even from Peek (which stays Peek) or a mini
    /// window; otherwise, the host turns it into a tab (or a mini window). A window opened for a context menu choice
    /// (task 5.9) follows that choice (`+PageMenu`).
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
    ) -> WKWebView? {
        guard let tabHost else {
            return nil
        }
        // The new page has its own content controller (blocker, task 6.2), not that of the originating page.
        WebConfigurationFactory.giveOwnContentController(to: configuration)
        let features = PopupWindowFeatures(windowFeatures)
        if let intent = takePageMenuIntent(of: webView, for: navigationAction, features: features) {
            return openWindow(for: intent, configuration: configuration, url: navigationAction.request.url, from: webView, in: tabHost)
        }
        guard features.opensPopupWindow, let popupWindows = tabHost.popupWindows else {
            return tabHost.openWindow(configuration: configuration, from: webView, inBackground: false)
        }
        // Never the address: only the host.
        let host = navigationAction.request.url?.host() ?? "?"
        Logger.browser.info("Sign-in window opened (\(host, privacy: .private))")
        return popupWindows.open(configuration: configuration, features: features, opener: PopupOpener(host: tabHost, webView: webView))
    }

    /// The page called `window.close()`.
    func webViewDidClose(_ webView: WKWebView) {
        tabHost?.closePage(of: webView)
    }
}
