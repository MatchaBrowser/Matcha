import Foundation
@testable import Matcha
import Testing
import WebKit

/// Pages et listes d'essai du bloqueur (tâche 6.2). Les listes du paquet des tests (`Fixtures/`) : « test-block »
/// bloque tout ce qui vient de `obtest://blocked.test/`, « test-hide » masque les éléments `.ad` de toute page. Une
/// page d'essai contient un tel élément et une image de `blocked.test` ; son titre dit si l'image s'est chargée.
@MainActor
enum BlockerTestPages {
    static let fixtures = BlocklistBundle(bundle: Bundle(for: TestPages.self), manifestName: "blocker-test-manifest.json")

    static let body = """
    <div class='ad'>pub</div>\
    <img src='obtest://blocked.test/a.svg' onload="document.title='loaded'" onerror="document.title='blocked'">
    """

    /// Page d'essai servie par `TestPages` sous l'hôte `host` (son « site » dans les tests).
    static func url(host: String = "pages") -> URL {
        var components = URLComponents()
        components.scheme = TestPages.scheme
        components.host = host
        components.path = "/page"
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    /// Magasin de listes compilées dans un dossier temporaire neuf (à effacer après le test), jamais celui de l'app.
    static func temporaryStore() throws -> (store: WKContentRuleListStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ContentRuleLists-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (WKContentRuleListStore(url: directory), directory)
    }

    /// Bloqueur dont le site d'une page `obtest:` est son hôte (« excepted.test »).
    static func service(defaults: UserDefaults? = nil) -> ContentBlockerService {
        let service = ContentBlockerService(defaults: defaults)
        service.siteOfURL = { $0?.host() }
        return service
    }

    /// État de la page de `tab` une fois chargée : l'image (« loaded » ou « blocked ») et l'affichage de l'élément `.ad`.
    static func outcome(of tab: BrowserTab, line: Int = #line) async throws -> Outcome {
        try await waitUntil(line: line) { tab.title == "loaded" || tab.title == "blocked" }
        let script = "getComputedStyle(document.querySelector('.ad')).display"
        let display = try await tab.loadedWebView.evaluateJavaScript(script) as? String
        return Outcome(imageLoaded: tab.title == "loaded", adHidden: display == "none")
    }

    /// Prépare un rechargement : le titre de la page est effacé pour attendre celui de la nouvelle.
    static func forgetOutcome(of tab: BrowserTab) async throws {
        _ = try await tab.loadedWebView.evaluateJavaScript("document.title = 'stale'; true")
        try await waitUntil { tab.title == "stale" }
    }

    struct Outcome: Equatable {
        let imageLoaded: Bool
        let adHidden: Bool

        static let blocked = Outcome(imageLoaded: false, adHidden: true)
        static let open = Outcome(imageLoaded: true, adHidden: false)
    }
}
