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

/// Waits until `condition` becomes true, checking it every 20 ms: the one wait of the tests (review TS14). 30 s by
/// default: loading a page (especially a real file, `file:`) takes less than a second alone, but more than 10 s when the
/// whole suite runs in parallel (web views and main thread shared); a true condition does not wait any longer because
/// of it. After `timeout`, an issue is recorded where it is called (`sourceLocation`) and the test stops.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(30),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            try #require(condition(), "Condition still false after \(timeout)", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// True once `condition` holds, false after `timeout`, without recording an issue: for a step the test tries again
/// (`waitUntil` would fail the test at the first miss).
@MainActor
func holds(within timeout: Duration, _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            return false
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// The value a callback API gives (WebKit, a delegate): a callback never called fails the test after `timeout`, where
/// it is called, instead of holding the whole suite (review TS1).
@MainActor
func awaitCallback<Value: Sendable>(
    timeout: Duration = .seconds(30),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ start: (@escaping @MainActor @Sendable (Value) -> Void) -> Void,
) async throws -> Value {
    // `.some` even for an optional value: only the deadline gives nil.
    let value: Value? = await CallbackTimeout.value(timeout: timeout, fallback: nil) { done in
        start { done(.some($0)) }
    }
    return try #require(value, "Callback not called after \(timeout)", sourceLocation: sourceLocation)
}

/// `waitUntil` for a condition read asynchronously: a page's script, an actor.
@MainActor
func waitUntilAsync(
    timeout: Duration = .seconds(30),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async throws -> Bool,
) async throws {
    let deadline = ContinuousClock.now + timeout
    while try await !condition() {
        guard ContinuousClock.now < deadline else {
            try #require(try await condition(), "Condition still false after \(timeout)", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// `value`, which the test knows is there; nil records an issue where it is used and gives `fallback`, rather than a
/// forced unwrap, which would crash the host app and fail every test still running (review TS13). For a value built
/// outside a throwing context (a constant, a fake); elsewhere, `try #require`.
func required<Value>(
    _ value: Value?,
    else fallback: @autoclosure () -> Value,
    sourceLocation: SourceLocation = #_sourceLocation,
) -> Value {
    guard let value else {
        Issue.record("Unexpected nil", sourceLocation: sourceLocation)
        return fallback()
    }
    return value
}

/// The address `string` (relative to `base`), which the test knows is valid (`required`).
func testURL(_ string: String, relativeTo base: URL? = nil, sourceLocation: SourceLocation = #_sourceLocation) -> URL {
    required(URL(string: string, relativeTo: base), else: URL(filePath: "/invalid-test-address"), sourceLocation: sourceLocation)
}

/// The origin `scheme://host:port`, which the test knows is valid (`required`).
func testOrigin(_ scheme: String, _ host: String, port: Int? = nil, sourceLocation _: SourceLocation = #_sourceLocation) -> SiteOrigin {
    // swiftlint:disable:next force_unwrapping
    required(SiteOrigin(scheme: scheme, host: host, port: port), else: SiteOrigin(scheme: "https", host: "invalid.test", port: nil)!)
}

/// Defaults suites of a test, erased with it (review TS3): the tests run in Matcha's own container, where a suite left
/// behind, even emptied by `removePersistentDomain`, stays as a plist. Held by the test (a property of its type): when
/// the test ends, each suite made by `make` is emptied and its file deleted.
final class TestDefaults: @unchecked Sendable {
    private let prefix: String
    private var names: [String] = []

    init(_ prefix: String = "MatchaTests") {
        self.prefix = prefix
    }

    /// A new, empty suite.
    func make() -> UserDefaults {
        let name = "\(prefix)-\(UUID().uuidString)"
        names.append(name)
        return required(UserDefaults(suiteName: name), else: .standard)
    }

    deinit {
        names.forEach(Self.erase)
    }

    /// Empties the suite `name` and deletes its file.
    static func erase(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        if let file = library?.appending(path: "Preferences/\(name).plist") {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

extension Trait where Self == TimeLimitTrait {
    /// Most a test that drives WebKit may last (review TS1): a callback that never comes fails that test, never holds
    /// the whole suite (the CI stops after 60 minutes).
    static var webKit: Self {
        .timeLimit(.minutes(2))
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
        return required(components.url, else: URL(filePath: "/invalid-test-address"))
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
