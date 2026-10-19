import OSLog
import WebKit

/// Downloads a page starts on its own (audit W7): a second download, or one from a frame inside the page, waits for the
/// user's answer in the page's banner (“Don't Allow”, “Allow”, “Always Allow” for the website), unless it follows a
/// real click (`DownloadConsentPolicy`). Meanwhile WebKit waits for the decision; the downloads that come in the
/// meantime wait for the same answer. A new document or a closed page declines them.
extension NavigationCoordinator {
    /// A real click on a link or a form button (a script's click has no mouse button).
    func recordClick(_ navigationAction: WKNavigationAction, in webView: WKWebView) {
        guard [.linkActivated, .formSubmitted].contains(navigationAction.navigationType), navigationAction.buttonNumber != 0 else {
            return
        }
        tabHost?.page(for: webView)?.pageDownloads.userDidClick(at: now())
    }

    /// `decide` gets true if the download goes ahead, at once or once the user has answered.
    func startDownload(in webView: WKWebView, isSubframe: Bool, decide: @escaping @MainActor (Bool) -> Void) {
        guard let page = tabHost?.page(for: webView) else {
            decide(true)
            return
        }
        let downloads = page.pageDownloads
        let origin = webView.url.flatMap(SiteOrigin.init(url:))
        let scope = tabHost?.sitePermissions(for: webView)
        let isAllowedForSite = origin.map { scope?.isAllowed(.downloadFiles, origin: $0) == true } ?? false
        let needsConsent = DownloadConsentPolicy.needsConsent(
            isAllowed: downloads.isAllowed || isAllowedForSite,
            lastClick: downloads.lastClick,
            now: now(),
            isSubframe: isSubframe,
            earlierDownloads: downloads.started,
        )
        guard needsConsent else {
            downloads.didStart()
            decide(true)
            return
        }
        let isFirstWaiting = !downloads.isWaiting
        downloads.hold { allowed in
            if allowed {
                downloads.didStart()
            }
            decide(allowed)
        }
        guard isFirstWaiting else {
            Logger.downloads.info("Téléchargement en attente avec les précédents")
            return
        }
        Logger.downloads.info("Téléchargement sans clic : en attente dans le bandeau")
        page.permissionPrompts.enqueue(SiteActionRequest(
            action: .downloadFiles,
            origin: origin,
            scope: scope,
            perform: { downloads.release(allowing: true) },
            decline: { downloads.release(allowing: false) },
        ))
    }
}
