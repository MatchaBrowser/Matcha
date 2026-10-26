import OSLog
import WebKit

/// Notifications of the pages (`PageNotificationScript`): the decision is the profile's, per origin, like the camera's
/// (`SitePermissionKind.notifications`), asked in the page's banner. Checked here too, whatever the scripts say (review
/// WB2): only the main frame of a website in a secure context (https, or http on this Mac) may ask, once at a time;
/// a frame of the same website may notify, never one of another site; nothing in a private window, where nothing is
/// remembered.
extension NavigationCoordinator: PageNotificationReceiving {
    /// Message of the notification script of `frame`; `reply` settles the script's promise.
    func receive(
        _ message: PageNotificationMessage,
        from frame: WKFrameInfo,
        in webView: WKWebView,
        reply: @escaping @MainActor @Sendable (Any?) -> Void,
    ) {
        switch message {
        case .requestPermission:
            requestNotifications(from: frame, in: webView) { reply($0.rawValue) }
        case let .show(content):
            showNotification(content, from: frame, in: webView) { reply($0) }
        case let .close(scriptID):
            notificationCenter?.close(scriptID: scriptID, in: webView)
            reply(nil)
        }
    }

    /// Before a navigation of the main frame to `destination`: the decision of its website, read by the script of the
    /// next documents (review WB10: only this one).
    func prepareNotifications(for webView: WKWebView, destination: URL?) {
        guard let notificationCenter else {
            return
        }
        let scope = notificationScope(for: webView)
        let origin = SiteOrigin.web(of: destination)
        let permission = PageNotificationPermission(origin.flatMap { scope?.decision(.notifications, for: $0) })
        notificationCenter.prepare(webView, isAvailable: scope != nil, origin: origin?.key, permission: permission)
    }

    /// The decision of `origin` changed in the settings while `page` shows it (`BrowserSession`, review IU16): its
    /// displayed document reads it at once (review WB10).
    func notificationDecisionDidChange(_ decision: SitePermissionDecision?, origin: SiteOrigin, on page: BrowserTab) {
        guard let notificationCenter, let webView = page.webView, notificationScope(for: webView) != nil else {
            return
        }
        notificationCenter.update(webView, origin: origin.key, permission: PageNotificationPermission(decision))
    }

    /// New document: the page may notify, and is then never put to sleep (task 5.6), if its website is allowed.
    func notificationsDocumentDidChange(in webView: WKWebView, page: BrowserTab) {
        let origin = SiteOrigin.web(of: webView.url)
        page.canSendNotifications = origin.map { notificationScope(for: webView)?.decision(.notifications, for: $0) == .allow } ?? false
    }

    /// Decisions of the profile of `webView`; nil without a notification center or in a private window.
    private func notificationScope(for webView: WKWebView) -> SitePermissionScope? {
        guard notificationCenter != nil, let scope = tabHost?.sitePermissions(for: webView), scope.store.isPersistent else {
            return nil
        }
        return scope
    }

    /// Website of `frame` if it may use notifications: that of the displayed document (never the one being loaded), in a
    /// secure context.
    private func notificationOrigin(of frame: WKFrameInfo, in webView: WKWebView) -> SiteOrigin? {
        guard let origin = frame.securityOrigin.siteOrigin, origin.isSecureContext,
              origin == SiteOrigin.web(of: displayedDocument(of: webView))
        else {
            return nil
        }
        return origin
    }

    /// `Notification.requestPermission()`: the remembered decision, or the page's banner. Allowed: macOS asks once
    /// whether Matcha may show notifications.
    private func requestNotifications(
        from frame: WKFrameInfo,
        in webView: WKWebView,
        reply: @escaping @MainActor @Sendable (PageNotificationPermission) -> Void,
    ) {
        guard notificationScope(for: webView) != nil, frame.isMainFrame, let origin = notificationOrigin(of: frame, in: webView) else {
            Logger.notifications.notice("Notification request denied: private window, insecure page or frame")
            reply(.denied)
            return
        }
        if tabHost?.page(for: webView)?.permissionPrompts.isAsking([.notifications], origin: origin) == true {
            // Already in the banner: a page can't pile up the same request.
            reply(.default)
            return
        }
        let response = PermissionResponse { [weak self, weak webView] granted in
            reply(granted ? .granted : .denied)
            guard granted, let self, let webView else {
                return
            }
            tabHost?.page(for: webView)?.canSendNotifications = true
            Task { await self.notificationCenter?.requestAuthorization() }
        }
        requestPermission([.notifications], origin: origin, frameOrigin: origin, in: webView, response: response)
    }

    /// `new Notification(…)`: shown if the website is allowed; `reply` receives false otherwise (`error` event).
    private func showNotification(
        _ content: PageNotificationContent,
        from frame: WKFrameInfo,
        in webView: WKWebView,
        reply: @escaping @MainActor @Sendable (Bool) -> Void,
    ) {
        guard let notificationCenter, let scope = notificationScope(for: webView),
              let origin = notificationOrigin(of: frame, in: webView),
              scope.decision(.notifications, for: origin) == .allow,
              let page = tabHost?.page(for: webView)
        else {
            Logger.notifications.notice("Notification refused: website not allowed")
            reply(false)
            return
        }
        Task {
            let sender = PageNotificationCenter.Sender(page: page, webView: webView, frame: frame)
            await reply(notificationCenter.post(content, origin: origin, profileID: scope.profileID, from: sender))
        }
    }
}
