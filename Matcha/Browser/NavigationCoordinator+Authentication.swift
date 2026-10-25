import OSLog
import Security
import WebKit

/// Websites protected by a user name and password (HTTP authentication, audit K3): a sheet on the page's window names
/// the server and asks for them; they are kept for the session only. Cancelled: the server's own refusal page shows.
/// Only for the website of the page or of its load, one sheet at a time per protected area, and the user can stop them
/// like JavaScript dialogs (review WB6).
/// Certificates are left to the system, except an invalid one the user chose to accept for that website (“Visit This
/// Website Anyway”, `CertificateExceptions`): every page whose document comes over it then says “Not Secure”.
extension NavigationCoordinator {
    func webView(
        _ webView: WKWebView,
        respondTo challenge: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            return serverTrustAnswer(for: space, in: webView)
        }
        let pageHosts = [webView.url?.host(), displayedDocument(of: webView)?.host()]
        guard LoginRequest.asksForPassword(space.authenticationMethod), let page = tabHost?.page(for: webView),
              LoginRequest.mayAsk(
                  method: space.authenticationMethod,
                  failures: challenge.previousFailureCount,
                  host: space.host,
                  pageHosts: pageHosts,
              ),
              !page.pageDialogs.isSuppressed
        else {
            return (.performDefaultHandling, nil)
        }
        guard let credential = await login(for: challenge, in: webView, page: page) else {
            return (.rejectProtectionSpace, nil)
        }
        return (.useCredential, credential)
    }

    /// The sheet's answer; a challenge for an area whose sheet is already on screen gets the same one.
    private func login(for challenge: URLAuthenticationChallenge, in webView: WKWebView, page: BrowserTab) async -> URLCredential? {
        let space = challenge.protectionSpace
        let key = LoginRequest.key(of: space)
        if let pending = page.pageDialogs.pendingLogins[key] {
            return await pending.value?.credential
        }
        let site = SiteOrigin(scheme: space.protocol ?? "https", host: space.host, port: space.port)?.displayName ?? space.host
        let login = LoginRequest(
            site: site,
            realm: space.realm,
            isSecure: space.receivesCredentialSecurely,
            failedBefore: challenge.previousFailureCount > 0,
            user: challenge.proposedCredential?.user,
            offersSuppression: page.pageDialogs.shown > 0,
        )
        page.pageDialogs.didShow()
        let dialogs = dialogs
        let sheet = Task { await dialogs.credential(for: login, for: webView) }
        page.pageDialogs.pendingLogins[key] = sheet
        let answer = await sheet.value
        page.pageDialogs.pendingLogins[key] = nil
        if answer?.suppressesFurther == true {
            page.pageDialogs.suppress()
            Logger.browser.info("Page dialogs stopped by the user")
        }
        return answer?.credential
    }

    /// The system's evaluation, unless the user accepted this exact certificate for this website: the page then shows
    /// “Not Secure”.
    func serverTrustAnswer(for space: URLProtectionSpace, in webView: WKWebView) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trust = space.serverTrust, let exceptions = tabHost?.sitePermissions(for: webView)?.store.certificateExceptions,
              exceptions.isAccepted(trust, host: space.host)
        else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }

    /// New document in `page`: “Not Secure” if its connection uses a certificate the user accepted. Read from the web
    /// view's own certificate: a tab reusing the connection another tab opened gets no challenge (review WB5).
    func updateCertificateException(of page: BrowserTab, in webView: WKWebView) {
        let exceptions = tabHost?.sitePermissions(for: webView)?.store.certificateExceptions
        page.usesAcceptedCertificate = Self.usesAcceptedCertificate(webView.serverTrust, host: webView.url?.host(), exceptions: exceptions)
    }

    static func usesAcceptedCertificate(_ trust: SecTrust?, host: String?, exceptions: CertificateExceptions?) -> Bool {
        guard let trust, let host, let exceptions else {
            return false
        }
        return exceptions.isAccepted(trust, host: host)
    }
}
