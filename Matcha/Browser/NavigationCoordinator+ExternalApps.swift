import AppKit
import OSLog
import WebKit

/// Links to other apps (audit W2): nothing opens without the user. A link to another app, clicked or followed by a
/// script or a redirection, waits in the page's banner, which names the site and the app: “Cancel”, “Open”, “Always
/// Open” (remembered for this website and this kind of link, `SiteActionAllowances`). Nothing happens if no app
/// handles the link; a page can't pile up the same request. A choice in the page's menu opens a mail or phone link at
/// once, any other one through the banner (`+PageMenu`). File shares and remote sessions never open
/// (`NavigationPolicy.refusedSchemes`, review WB4).
extension NavigationCoordinator {
    /// `origin` is the website asking (`requester(of:in:)`): the banner names it, “Always Open” is remembered for it.
    func requestOpening(_ url: URL, from webView: WKWebView, origin: SiteOrigin?) {
        let scheme = url.scheme?.lowercased() ?? "?"
        guard !NavigationPolicy.isRefused(url) else {
            Logger.browser.notice("\(scheme, privacy: .public): link refused, never handed to another app")
            return
        }
        guard let page = tabHost?.page(for: webView) else {
            return
        }
        let action = SiteAction.openApp(scheme: scheme)
        // Before looking for the app (review WB23): a page that loops on the same link costs nothing, and a refused
        // request comes back only after a real click in the page.
        if page.permissionPrompts.isWaiting(for: action) {
            return
        }
        if let declined = page.permissionPrompts.declineDate(of: action), (page.pageDownloads.lastClick ?? .distantPast) <= declined {
            Logger.browser.notice("\(scheme, privacy: .public): link ignored, refused in this page without a click since")
            return
        }
        guard let appURL = applicationForURL(url) else {
            Logger.browser.notice("No app handles \(scheme, privacy: .public): links")
            return
        }
        let scope = tabHost?.sitePermissions(for: webView)
        if let origin, scope?.isAllowed(action, origin: origin) == true {
            open(externally: url)
            return
        }
        let request = SiteActionRequest(
            action: action,
            origin: origin,
            scope: scope,
            appName: FileManager.default.displayName(atPath: appURL.path),
            appIcon: NSWorkspace.shared.icon(forFile: appURL.path),
            perform: { [weak self] in self?.open(externally: url) },
        )
        if page.permissionPrompts.enqueue(request) {
            Logger.browser.info("\(scheme, privacy: .public): link waiting in the banner")
        } else {
            Logger.browser.notice("\(scheme, privacy: .public): link ignored, the same request is already waiting")
        }
    }
}
