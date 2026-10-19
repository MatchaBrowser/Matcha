import Foundation
import Security
import WebKit

/// Address and security shown for the tab's page (audit W4 and W5).
extension BrowserTab {
    /// Address to show: the displayed document's, or the one the user asked for while it loads.
    var displayedURL: URL? {
        displayedAddress.url
    }

    /// Security of the displayed page; nothing while a load asked for by the user is pending, or without a web view
    /// (tab not loaded or asleep: nothing is known about its connection).
    var security: PageSecurity {
        guard webView != nil, !displayedAddress.isPending else {
            return .none
        }
        return PageSecurity.of(displayedAddress.url, hasOnlySecureContent: hasOnlySecureContent)
    }

    /// Certificate chain and its evaluation, for an encrypted page.
    var serverTrust: SecTrust? {
        security.hasCertificate ? webView?.serverTrust : nil
    }
}
