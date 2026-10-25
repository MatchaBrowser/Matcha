import Foundation
import Security
import WebKit

/// Address and security shown for the tab's page (audit W4 and W5).
extension BrowserTab {
    /// Address to show or copy: the displayed document's, the one the user asked for while it loads, or the one that
    /// failed.
    var displayedURL: URL? {
        loadFailure.error?.url ?? displayedAddress.url
    }

    /// Address of the document on screen, for what acts on it (site settings, zoom, saving, source); never a load that
    /// isn't displayed yet (review TR1).
    var documentURL: URL? {
        displayedAddress.committed
    }

    /// Security of the displayed page; nothing while a load asked for by the user is pending, after a failed load, or
    /// without a web view (tab not loaded or asleep: nothing is known about its connection).
    var security: PageSecurity {
        guard webView != nil, !displayedAddress.isPending, loadFailure.error == nil else {
            return .none
        }
        if let host = displayedAddress.url?.host()?.lowercased(), acceptedCertificateHosts.contains(host) {
            return .invalidCertificate
        }
        return PageSecurity.of(displayedAddress.url, hasOnlySecureContent: hasOnlySecureContent)
    }

    /// Certificate chain and its evaluation, for an encrypted page.
    var serverTrust: SecTrust? {
        security.hasCertificate ? webView?.serverTrust : nil
    }
}
