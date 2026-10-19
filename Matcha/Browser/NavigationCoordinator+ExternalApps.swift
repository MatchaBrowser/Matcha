import AppKit
import OSLog
import WebKit

/// Links to other apps (audit W2): nothing opens without the user. A link to another app, clicked or followed by a
/// script or a redirection, waits in the page's banner, which names the site and the app: “Cancel”, “Open”, “Always
/// Open” (remembered for this website and this kind of link, `SiteActionAllowances`). Nothing happens if no app
/// handles the link; a page can't pile up the same request. A choice in the page's menu opens directly (`+PageMenu`).
extension NavigationCoordinator {
    func requestOpening(_ url: URL, from webView: WKWebView) {
        let scheme = url.scheme?.lowercased() ?? "?"
        guard let appURL = applicationForURL(url) else {
            Logger.browser.notice("No app handles \(scheme, privacy: .public): links")
            return
        }
        guard let page = tabHost?.page(for: webView) else {
            return
        }
        let action = SiteAction.openApp(scheme: scheme)
        let origin = webView.url.flatMap(SiteOrigin.init(url:))
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
