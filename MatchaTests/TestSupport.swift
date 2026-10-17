import Foundation
@testable import Matcha
import WebKit

extension BrowserTab {
    /// Vue web de l'onglet, créée si besoin.
    var loadedWebView: WKWebView {
        makeWebViewIfNeeded()
    }
}

struct WaitTimeoutError: Error, CustomStringConvertible {
    let line: Int
    var description: String {
        "Condition toujours fausse à la ligne \(line)"
    }
}

/// Attend que `condition` devienne vraie, en la vérifiant toutes les 20 ms.
@MainActor
func waitUntil(timeout: Duration = .seconds(10), line: Int = #line, _ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else {
            throw WaitTimeoutError(line: line)
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// Sert des pages HTML locales sous le schéma `obtest:`, pour tester la navigation sans réseau.
/// `obtest://pages/<nom>` renvoie une page dont le titre est `<nom>` ; le paramètre `body`
/// fournit le contenu HTML du corps.
@MainActor
final class TestPages: NSObject, WKURLSchemeHandler {
    static let scheme = "obtest"

    static func url(_ name: String, body: String = "") -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "pages"
        components.path = "/\(name)"
        if !body.isEmpty {
            components.queryItems = [URLQueryItem(name: "body", value: body)]
        }
        return components.url!
    }

    /// Configuration de l'app, avec en plus le schéma `obtest:`.
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent())
        configuration.setURLSchemeHandler(TestPages(), forURLScheme: scheme)
        return configuration
    }

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let title = url.lastPathComponent
        let body = components?.queryItems?.first { $0.name == "body" }?.value ?? ""
        let html = "<!doctype html><html><head><title>\(title)</title></head><body>\(body)</body></html>"
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: -1, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data(html.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
