import Foundation
@testable import Matcha
import Testing
import WebKit

/// Blocker with WebKit (task 6.2): test lists compiled into a temporary store, then real pages
/// (`BlockerTestPages`) in the tabs of a Space: blocked image and hidden element, lists set afterwards, global
/// setting, site exception (its pages reload), private window, window opened by a page.
@MainActor
final class ContentBlockerIntegrationTests {
    private let service = BlockerTestPages.service()
    private let store: WKContentRuleListStore
    private let directory: URL
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    init() throws {
        (store, directory) = try BlockerTestPages.temporaryStore()
        manager.contentBlocking = ContentBlockerScope(service: service, savesExceptions: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func open(host: String = "pages", in manager: TabManager? = nil) -> BrowserTab {
        let tab = (manager ?? self.manager).insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(BlockerTestPages.url(host: host))
        return tab
    }

    private func reload(_ tab: BrowserTab) async throws -> BlockerTestPages.Outcome {
        try await BlockerTestPages.forgetOutcome(of: tab)
        tab.webView?.reload()
        return try await BlockerTestPages.outcome(of: tab)
    }

    @Test func `the test lists are compiled and listed`() async {
        await service.load(from: BlockerTestPages.fixtures, store: store)
        #expect(service.state == .ready)
        #expect(service.installedLists.map(\.entry.name) == ["Test Block", "Test Hide"])
        #expect(service.installedLists.map(\.record.ruleCount) == [1, 1])
        #expect(service.installedLists.first?.entry.homepageURL == URL(string: "https://example.com/lists"))
        #expect(await store.identifiers().sorted() == ["matcha-blocklist.test-block.1", "matcha-blocklist.test-hide.1"])
    }

    /// Second launch: the lists are read back as they are (same compilation date), without recompiling.
    @Test func `a second launch reuses the compiled lists`() async throws {
        let suiteName = "ContentBlockerIntegrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await BlockerTestPages.service(defaults: defaults).load(from: BlockerTestPages.fixtures, store: store)
        let first = CompiledBlocklist.load(from: defaults)
        #expect(first.count == 2)

        let relaunched = BlockerTestPages.service(defaults: defaults)
        await relaunched.load(from: BlockerTestPages.fixtures, store: store)
        #expect(relaunched.installedLists.map(\.record) == first)
        #expect(CompiledBlocklist.load(from: defaults) == first)
    }

    @Test func `pages load unblocked until the lists are ready, then they are blocked`() async throws {
        let tab = open()
        #expect(try await BlockerTestPages.outcome(of: tab) == .open)
        #expect(service.trackedPageCount == 1)

        await service.load(from: BlockerTestPages.fixtures, store: store)
        #expect(try await reload(tab) == .blocked)
        // A new page is blocked from its first load.
        #expect(try await BlockerTestPages.outcome(of: open()) == .blocked)
    }

    @Test func `the global switch applies from the next load`() async throws {
        await service.load(from: BlockerTestPages.fixtures, store: store)
        let tab = open()
        #expect(try await BlockerTestPages.outcome(of: tab) == .blocked)

        service.isEnabled = false
        #expect(try await reload(tab) == .open)
        service.isEnabled = true
        #expect(try await reload(tab) == .blocked)
    }

    /// A site exception reloads its pages, without touching other sites; removing it blocks them again.
    @Test func `an exception reloads the pages of its site unblocked`() async throws {
        await service.load(from: BlockerTestPages.fixtures, store: store)
        let excepted = open(host: "excepted.test")
        let other = open(host: "other.test")
        #expect(try await BlockerTestPages.outcome(of: excepted) == .blocked)
        #expect(try await BlockerTestPages.outcome(of: other) == .blocked)
        try await BlockerTestPages.forgetOutcome(of: excepted)
        try await BlockerTestPages.forgetOutcome(of: other)

        manager.contentBlocking?.setBlocks(false, onSite: "excepted.test")
        #expect(try await BlockerTestPages.outcome(of: excepted) == .open)
        #expect(other.title == "stale")
        #expect(try await reload(other) == .blocked)
        // A new tab of the site is not blocked either.
        #expect(try await BlockerTestPages.outcome(of: open(host: "excepted.test")) == .open)

        try await BlockerTestPages.forgetOutcome(of: excepted)
        manager.contentBlocking?.setBlocks(true, onSite: "excepted.test")
        #expect(try await BlockerTestPages.outcome(of: excepted) == .blocked)
    }

    /// An exception made in a private window only applies to its pages.
    @Test func `a private exception leaves the main session blocked`() async throws {
        await service.load(from: BlockerTestPages.fixtures, store: store)
        let privateManager = TabManager(websiteDataStore: .nonPersistent())
        let privateScope = ContentBlockerScope(service: service, savesExceptions: false)
        privateManager.contentBlocking = privateScope
        let main = open(host: "excepted.test")
        let privatePage = open(host: "excepted.test", in: privateManager)
        #expect(try await BlockerTestPages.outcome(of: main) == .blocked)
        #expect(try await BlockerTestPages.outcome(of: privatePage) == .blocked)
        try await BlockerTestPages.forgetOutcome(of: privatePage)

        privateScope.setBlocks(false, onSite: "excepted.test")
        #expect(try await BlockerTestPages.outcome(of: privatePage) == .open)
        #expect(try await reload(main) == .blocked)
        #expect(service.exceptions.sites.isEmpty)
    }

    /// A page opened by `window.open` has its own controller (otherwise the exception of one would affect the
    /// other), keeps `window.opener` and stays blocked.
    @Test func `a window opened by a page has its own controller`() async throws {
        await service.load(from: BlockerTestPages.fixtures, store: store)
        let opener = open(host: "excepted.test")
        #expect(try await BlockerTestPages.outcome(of: opener) == .blocked)
        // Encoded single quotes: the address goes into a single-quoted JavaScript string.
        let address = BlockerTestPages.url(host: "other.test").absoluteString.replacingOccurrences(of: "'", with: "%27")
        _ = try await opener.loadedWebView.evaluateJavaScript("window.open('\(address)'); true")
        try await waitUntil { manager.tabs.count == 2 }
        let popup = try #require(manager.tabs.first { $0 !== opener })
        #expect(try await BlockerTestPages.outcome(of: popup) == .blocked)
        #expect(try await popup.loadedWebView.evaluateJavaScript("window.opener !== null") as? Bool == true)
        let popupController = popup.loadedWebView.configuration.userContentController
        #expect(popupController !== opener.loadedWebView.configuration.userContentController)

        try await BlockerTestPages.forgetOutcome(of: opener)
        try await BlockerTestPages.forgetOutcome(of: popup)
        manager.contentBlocking?.setBlocks(false, onSite: "excepted.test")
        #expect(try await BlockerTestPages.outcome(of: opener) == .open)
        // The window (another site) has not been reloaded, and stays blocked.
        #expect(popup.title == "stale")
        #expect(try await reload(popup) == .blocked)
    }

    /// Navigation to another site that fails before showing anything: the page still shown (site with an
    /// exception) gets its state back, and an image it loads afterwards is not blocked.
    @Test func `a failed navigation leaves the displayed page as it was`() async throws {
        await service.load(from: BlockerTestPages.fixtures, store: store)
        manager.contentBlocking?.setBlocks(false, onSite: "excepted.test")
        let configuration = TestPages.configuration()
        let failing = FailingPages()
        configuration.setURLSchemeHandler(failing, forURLScheme: FailingPages.scheme)
        let tab = manager.insertTab(configuration: configuration, after: nil, select: true)
        tab.load(BlockerTestPages.url(host: "excepted.test"))
        #expect(try await BlockerTestPages.outcome(of: tab) == .open)

        try tab.load(#require(URL(string: "\(FailingPages.scheme)://other.test/")))
        try await waitUntil { failing.didFail && !tab.isLoading }
        let script = """
        const image = document.createElement('img');
        image.onload = () => document.title = 'late-loaded';
        image.onerror = () => document.title = 'late-blocked';
        image.src = 'obtest://blocked.test/late.svg';
        document.body.appendChild(image);
        return true;
        """
        _ = try await tab.loadedWebView.callAsyncJavaScript(script, contentWorld: .page)
        try await waitUntil { tab.title?.hasPrefix("late-") == true }
        #expect(tab.title == "late-loaded")
    }
}

/// Scheme whose every load fails (host not found), for a navigation that does not complete.
@MainActor
final class FailingPages: NSObject, WKURLSchemeHandler {
    static let scheme = "obfail"
    private(set) var didFail = false

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        didFail = true
        urlSchemeTask.didFailWithError(URLError(.cannotFindHost))
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
