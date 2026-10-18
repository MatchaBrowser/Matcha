import Foundation
@testable import Matcha
import Testing
import WebKit

extension BrowserTab {
    /// Vue web de l'onglet, créée si besoin.
    var loadedWebView: WKWebView {
        makeWebViewIfNeeded()
    }
}

/// Règles des splits (I1–I3), vérifiées après chaque changement dans les tests : 2 à 4 membres, une part par
/// membre (somme 1), groupes disjoints, membres rangés hors des favoris, voisins dans un même conteneur dans
/// l'ordre des panneaux, groupes triés par identifiant.
func expectSplitInvariants(_ layout: SidebarLayout, sourceLocation: SourceLocation = #_sourceLocation) {
    var seen: Set<UUID> = []
    for group in layout.splits {
        #expect(SplitGroup.paneCount.contains(group.tabIDs.count), sourceLocation: sourceLocation)
        #expect(group.fractions.count == group.tabIDs.count, sourceLocation: sourceLocation)
        #expect(abs(group.fractions.reduce(0, +) - 1) <= 1e-9, sourceLocation: sourceLocation)
        #expect(seen.isDisjoint(with: group.tabIDs), sourceLocation: sourceLocation)
        seen.formUnion(group.tabIDs)
        #expect(group.tabIDs.allSatisfy { [.pinned, .today].contains(layout.place(of: $0)) }, sourceLocation: sourceLocation)
        let locations = group.tabIDs.compactMap(layout.container(of:))
        #expect(locations.count == group.tabIDs.count, sourceLocation: sourceLocation)
        #expect(locations.allSatisfy { $0.container == locations.first?.container }, sourceLocation: sourceLocation)
        let start = locations.first?.index ?? 0
        #expect(locations.map(\.index) == Array(start ..< start + locations.count), sourceLocation: sourceLocation)
    }
    let ids = layout.splits.map(\.id.uuidString)
    #expect(ids == ids.sorted(), sourceLocation: sourceLocation)
}

struct WaitTimeoutError: Error, CustomStringConvertible {
    let line: Int
    var description: String {
        "Condition toujours fausse à la ligne \(line)"
    }
}

/// Attend que `condition` devienne vraie, en la vérifiant toutes les 20 ms. 30 s par défaut : le chargement d'une page
/// (surtout un vrai fichier, `file:`) prend moins d'une seconde seul, mais plus de 10 s quand toute la suite tourne en
/// parallèle (vues web et fil principal partagés) ; une condition vraie n'attend pas plus longtemps pour autant.
@MainActor
func waitUntil(timeout: Duration = .seconds(30), line: Int = #line, _ condition: () -> Bool) async throws {
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
/// fournit le contenu HTML du corps. Un nom en `.svg` renvoie une image (un carré bleu de 400 points).
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
        let isImage = url.pathExtension == "svg"
        let content = isImage
            ? "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400'><rect width='400' height='400' fill='blue'/></svg>"
            : "<!doctype html><html><head><title>\(title)</title></head><body>\(body)</body></html>"
        let mimeType = isImage ? "image/svg+xml" : "text/html"
        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: -1, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data(content.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
