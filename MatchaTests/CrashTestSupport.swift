import Foundation
@testable import Matcha
import WebKit

/// Pages locales de `TestPages` qui comptent les requêtes reçues, par nom de page : un rechargement (tâche 5.7) en
/// refait une. Aucune API privée ne permet d'arrêter le processus d'une page : les tests appellent directement
/// `webViewWebContentProcessDidTerminate(_:)` du délégué sur une vraie vue web.
@MainActor
final class CountingTestPages: NSObject, WKURLSchemeHandler {
    private(set) var requests: [String: Int] = [:]
    private let pages = TestPages()

    /// Configuration de l'app, avec ces pages sous le schéma `obtest:`.
    func configuration() -> WKWebViewConfiguration {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
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
