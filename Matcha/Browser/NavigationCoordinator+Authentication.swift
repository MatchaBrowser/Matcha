import WebKit

/// Websites protected by a user name and password (HTTP authentication, audit K3): a sheet on the page's window names
/// the server and asks for them; they are kept for the session only. Cancelled: the server's own refusal page shows.
/// Certificates are left to the system, except an invalid one the user chose to accept for that website (“Visit This
/// Website Anyway”, `CertificateExceptions`).
extension NavigationCoordinator {
    func webView(
        _ webView: WKWebView,
        respondTo challenge: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            return serverTrustAnswer(for: space, in: webView)
        }
        guard LoginRequest.asksForPassword(space.authenticationMethod), tabHost?.page(for: webView) != nil else {
            return (.performDefaultHandling, nil)
        }
        let site = SiteOrigin(scheme: space.protocol ?? "https", host: space.host, port: space.port)?.displayName ?? space.host
        let login = LoginRequest(
            site: site,
            realm: space.realm,
            isSecure: space.receivesCredentialSecurely,
            failedBefore: challenge.previousFailureCount > 0,
            user: challenge.proposedCredential?.user,
        )
        guard let credential = await dialogs.credential(for: login, for: webView) else {
            return (.rejectProtectionSpace, nil)
        }
        return (.useCredential, credential)
    }

    /// The system's evaluation, unless the user accepted this exact certificate for this website: the page then shows
    /// “Not Secure”.
    func serverTrustAnswer(for space: URLProtectionSpace, in webView: WKWebView) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trust = space.serverTrust, let exceptions = tabHost?.sitePermissions(for: webView)?.store.certificateExceptions,
              exceptions.isAccepted(trust, host: space.host)
        else {
            return (.performDefaultHandling, nil)
        }
        tabHost?.page(for: webView)?.acceptedCertificateHosts.insert(space.host.lowercased())
        return (.useCredential, URLCredential(trust: trust))
    }
}
