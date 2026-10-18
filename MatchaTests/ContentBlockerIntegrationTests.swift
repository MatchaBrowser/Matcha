import Foundation
@testable import Matcha
import Testing
import WebKit

/// Bloqueur avec WebKit (tâche 6.2) : listes d'essai compilées dans un magasin temporaire, puis de vraies pages
/// (`BlockerTestPages`) dans les onglets d'un Space : image bloquée et élément masqué, listes posées après coup,
/// réglage global, exception d'un site (ses pages se rechargent), fenêtre privée, fenêtre ouverte par une page.
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

    /// Second lancement : les listes sont relues telles quelles (même date de compilation), sans recompiler.
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
        // Une nouvelle page est bloquée dès son premier chargement.
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

    /// L'exception d'un site recharge ses pages, sans toucher aux autres sites ; la retirer les rebloque.
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
        // Un nouvel onglet du site n'est pas bloqué non plus.
        #expect(try await BlockerTestPages.outcome(of: open(host: "excepted.test")) == .open)

        try await BlockerTestPages.forgetOutcome(of: excepted)
        manager.contentBlocking?.setBlocks(true, onSite: "excepted.test")
        #expect(try await BlockerTestPages.outcome(of: excepted) == .blocked)
    }

    /// Une exception prise dans une fenêtre privée ne vaut que pour ses pages.
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

    /// Une page ouverte par `window.open` a son propre contrôleur (sans quoi l'exception de l'une toucherait l'autre),
    /// garde `window.opener` et reste bloquée.
    @Test func `a window opened by a page has its own controller`() async throws {
        await service.load(from: BlockerTestPages.fixtures, store: store)
        let opener = open(host: "excepted.test")
        #expect(try await BlockerTestPages.outcome(of: opener) == .blocked)
        // Apostrophes encodées : l'adresse va dans une chaîne JavaScript entre apostrophes.
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
        // La fenêtre (autre site) n'a pas été rechargée, et reste bloquée.
        #expect(popup.title == "stale")
        #expect(try await reload(popup) == .blocked)
    }

    /// Navigation vers un autre site qui échoue avant d'afficher quoi que ce soit : la page restée affichée (site en
    /// exception) retrouve son état, et une image qu'elle charge ensuite n'est pas bloquée.
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

/// Schéma dont chaque chargement échoue (hôte introuvable), pour une navigation qui n'aboutit pas.
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
