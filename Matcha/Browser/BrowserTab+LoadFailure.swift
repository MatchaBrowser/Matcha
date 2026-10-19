import Foundation
import OSLog
import Security
import WebKit

/// A load that failed (audit K5): WebKit shows nothing, the tab shows why, with “Try Again”. Like an error page of
/// Safari: “Back” returns to the page it was leaving; the address shown is the one that failed.
extension BrowserTab {
    /// The main frame's load failed before showing anything; `certificateExceptions`: where the user can accept an
    /// invalid certificate.
    func provisionalLoadDidFail(_ error: any Error, certificateExceptions: CertificateExceptions? = nil) {
        let error = error as NSError
        let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        guard let pageError = PageLoadError(error, url: url) else {
            return
        }
        loadFailure.show(pageError, serverTrust: Self.serverTrust(of: error), certificateExceptions: certificateExceptions)
        keepFailedAddress(pageError.url)
        updateCanGoBack()
    }

    /// Certificate given with a certificate error.
    private static func serverTrust(of error: NSError) -> SecTrust? {
        guard let value = error.userInfo[NSURLErrorFailingURLPeerTrustErrorKey],
              CFGetTypeID(value as CFTypeRef) == SecTrustGetTypeID()
        else {
            return nil
        }
        // A Core Foundation type can only be cast unconditionally; its type was just checked.
        // swiftlint:disable:next force_cast
        return (value as! SecTrust)
    }

    /// “Try Again”, ⌘R: the address that failed, as asked for by the user.
    func retryFailedLoad() -> Bool {
        guard let error = loadFailure.error else {
            return false
        }
        load(error.url)
        return true
    }

    /// “Visit This Website Anyway”, asked by the user after a certificate error: this certificate is accepted for this
    /// website until the app quits, then the page loads again. The address pill then says “Not Secure”, in red.
    func visitDespiteInvalidCertificate() {
        guard loadFailure.canVisitAnyway, let error = loadFailure.error, let trust = loadFailure.serverTrust else {
            return
        }
        loadFailure.certificateExceptions?.accept(trust, host: error.host)
        Logger.browser.notice("Certificat non valide accepté par l'utilisateur pour la session")
        load(error.url)
    }

    /// “Back” with a failure shown over a page: back to that page.
    func leaveLoadFailure() -> Bool {
        guard loadFailure.error != nil, webView?.url != nil else {
            return false
        }
        loadFailure.clear()
        updateCanGoBack()
        return true
    }
}
