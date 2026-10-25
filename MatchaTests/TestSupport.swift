import Foundation
@testable import Matcha
import Testing
import WebKit

extension BrowserTab {
    /// The tab's web view, created if needed.
    var loadedWebView: WKWebView {
        makeWebViewIfNeeded()
    }
}

/// Split rules (I1–I3), checked after every change in the tests: 2 to 4 members, one share per member (sum 1),
/// disjoint groups, members placed outside the favorites, adjacent in the same container in pane order, groups sorted
/// by identifier.
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
        "Condition still false at line \(line)"
    }
}

/// Waits until `condition` becomes true, checking it every 20 ms. 30 s by default: loading a page (especially a real
/// file, `file:`) takes less than a second alone, but more than 10 s when the whole suite runs in parallel (web views
/// and main thread shared); a true condition does not wait any longer because of it.
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

/// Serves local HTML pages under the `obtest:` scheme, to test navigation without network.
/// `obtest://pages/<name>` returns a page whose title is `<name>`; the `body` parameter
/// provides the HTML content of the body. A name ending in `.svg` returns an image (a blue square of 400 points).
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

    /// The app's configuration, with the `obtest:` scheme added.
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent())
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

/// Pages that never answer: their load stays pending (a site that doesn't respond, audit W4).
@MainActor
final class SilentPages: NSObject, WKURLSchemeHandler {
    static let scheme = "obtest-lent"

    func webView(_: WKWebView, start _: any WKURLSchemeTask) {}

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
