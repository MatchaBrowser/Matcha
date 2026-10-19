import Foundation
@testable import Matcha
import Testing
import WebKit

/// Test pages and lists for the blocker (task 6.2). The lists of the test bundle (`Fixtures/`): “test-block”
/// blocks everything coming from `obtest://blocked.test/`, “test-hide” hides the `.ad` elements of any page. A test
/// page contains such an element and an image from `blocked.test`; its title says whether the image loaded.
@MainActor
enum BlockerTestPages {
    static let fixtures = BlocklistBundle(bundle: Bundle(for: TestPages.self), manifestName: "blocker-test-manifest.json")

    static let body = """
    <div class='ad'>pub</div>\
    <img src='obtest://blocked.test/a.svg' onload="document.title='loaded'" onerror="document.title='blocked'">
    """

    /// Test page served by `TestPages` under the host `host` (its “site” in the tests).
    static func url(host: String = "pages") -> URL {
        var components = URLComponents()
        components.scheme = TestPages.scheme
        components.host = host
        components.path = "/page"
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    /// Compiled list store in a new temporary folder (to delete after the test), never the app's own.
    static func temporaryStore() throws -> (store: WKContentRuleListStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ContentRuleLists-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (WKContentRuleListStore(url: directory), directory)
    }

    /// Blocker for which the site of an `obtest:` page is its host (“excepted.test”).
    static func service(defaults: UserDefaults? = nil) -> ContentBlockerService {
        let service = ContentBlockerService(defaults: defaults)
        service.siteOfURL = { $0?.host() }
        return service
    }

    /// State of the page of `tab` once loaded: the image (“loaded” or “blocked”) and the display of the `.ad` element.
    static func outcome(of tab: BrowserTab, line: Int = #line) async throws -> Outcome {
        try await waitUntil(line: line) { tab.title == "loaded" || tab.title == "blocked" }
        let script = "getComputedStyle(document.querySelector('.ad')).display"
        let display = try await tab.loadedWebView.evaluateJavaScript(script) as? String
        return Outcome(imageLoaded: tab.title == "loaded", adHidden: display == "none")
    }

    /// Prepares a reload: the page title is cleared so as to wait for the new page's title.
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
