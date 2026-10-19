import Foundation
@testable import Matcha
import WebKit

/// Local pages of `TestPages` that count the requests they receive, per page name: a reload (task 5.7) makes one
/// more. Only a private API could stop a page's process: the tests call the delegate's
/// `webViewWebContentProcessDidTerminate(_:)` directly on a real web view.
@MainActor
final class CountingTestPages: NSObject, WKURLSchemeHandler {
    private(set) var requests: [String: Int] = [:]
    private let pages = TestPages()

    /// App configuration, with these pages under the `obtest:` scheme.
    func configuration() -> WKWebViewConfiguration {
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent())
        configuration.setURLSchemeHandler(self, forURLScheme: TestPages.scheme)
        return configuration
    }

    func count(_ name: String) -> Int {
        requests[name, default: 0]
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        if let name = urlSchemeTask.request.url?.lastPathComponent {
            requests[name, default: 0] += 1
        }
        pages.webView(webView, start: urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        pages.webView(webView, stop: urlSchemeTask)
    }
}
