import Foundation
@testable import Matcha
import Testing
import WebKit

/// Loading extensions and WebKit (task 6.3), with the test extension (`TestExtension`).
@MainActor
struct ExtensionManagerTests {
    @Test func `the test extension loads under a stable identifier`() async throws {
        let manager = TestExtension.manager()
        let identifier = TestExtension.uniqueIdentifier()
        let (context, folder) = try await TestExtension.load(in: manager, identifier: identifier)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(context.isLoaded)
        #expect(context.webExtension.errors.isEmpty)
        #expect(context.uniqueIdentifier == identifier)
        #expect(context.baseURL == URL(string: "webkit-extension://\(identifier)/"))
        #expect(manager.contexts[identifier] === context)
        #expect(manager.store.state(for: identifier)?.isEnabled == true)
        #expect(!context.hasAccessToPrivateData)
        await #expect(throws: ExtensionError.alreadyLoaded(identifier)) {
            try await manager.load(resourceBaseURL: folder, identifier: identifier)
        }
        await #expect(throws: ExtensionError.invalidIdentifier("Matcha Test")) {
            try await manager.load(resourceBaseURL: folder, identifier: "Matcha Test")
        }
        manager.unload(identifier: identifier)
        #expect(!context.isLoaded)
        #expect(manager.contexts.isEmpty)
    }

    @Test func `every page configuration of the app gets its controller`() {
        let environment = AppEnvironment()
        let configuration = environment.pages.makeConfiguration(websiteDataStore: .nonPersistent())
        #expect(configuration.webExtensionController === environment.extensions.controller)
        let page = WebConfigurationFactory.pageConfiguration(from: WebConfigurationFactory.pageConfiguration(from: configuration))
        #expect(page.webExtensionController === environment.extensions.controller)
        // A factory made without extensions (tests) attaches none.
        #expect(WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent()).webExtensionController == nil)
    }

    @Test func `extension pages are never handed to another app`() throws {
        let coordinator = NavigationCoordinator()
        let webView = WKWebView(frame: .zero, configuration: TestPages.configuration())
        let url = try #require(URL(string: "webkit-extension://matcha-test/options.html"))
        #expect(coordinator.handles(url, in: webView))
        #expect(ExtensionManager.isExtensionURL(url))
        #expect(!ExtensionManager.isExtensionURL(URL(string: "https://example.com")))
    }

    @Test func `extension pages get their extension configuration`() async throws {
        let manager = TestExtension.manager()
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        let page = try #require(manager.pageConfiguration(for: context.baseURL.appendingPathComponent("options.html")))
        #expect(page.webExtensionController === manager.controller)
        #expect(try manager.pageConfiguration(for: #require(URL(string: "https://example.com"))) == nil)
    }

    // MARK: Pages

    /// `obtest:` page in a tab attached to `manager`, with the data store `store`.
    private func page(_ url: URL, store: WKWebsiteDataStore, manager: ExtensionManager) async throws -> BrowserTab {
        let configuration = TestPages.configuration()
        configuration.websiteDataStore = store
        manager.attach(to: configuration)
        let tab = BrowserTab(configuration: configuration)
        tab.load(url)
        try await waitUntil { tab.title == url.lastPathComponent && !tab.isLoading }
        return tab
    }

    /// Waits for the content script's mark (“1”); returns the last one read.
    private func marker(of tab: BrowserTab, expecting expected: String, attempts: Int = 100) async throws -> String? {
        var value: String?
        for _ in 0 ..< attempts {
            value = await TestExtension.marker(in: tab.loadedWebView)
            if value == expected {
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return value
    }

    /// Persistent store with a new identifier (a profile's pages), deleted after `body` (otherwise at the next launch
    /// of the app, which removes the stores without a profile).
    private func withProfileStore(_ body: (WKWebsiteDataStore) async throws -> Void) async throws {
        let identifier = UUID()
        try await body(WKWebsiteDataStore(forIdentifier: identifier))
        try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
    }

    @Test func `content scripts run in the pages of a profile`() async throws {
        let manager = TestExtension.manager()
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await TestExtension.waitForBackground(of: context)
        try await withProfileStore { store in
            let tab = try await page(TestPages.url("page"), store: store, manager: manager)
            #expect(try await marker(of: tab, expecting: "1") == "1")
            tab.unload(resettingTo: nil, title: nil)
        }
    }

    @Test func `private pages get nothing until the extension is allowed there`() async throws {
        let manager = TestExtension.manager()
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await TestExtension.waitForBackground(of: context)
        // Non-persistent store: a private page for WebKit.
        let tab = try await page(TestPages.url("page"), store: .nonPersistent(), manager: manager)
        #expect(try await marker(of: tab, expecting: "1", attempts: 10) == "none")
        manager.setAccessToPrivateData(true, identifier: context.uniqueIdentifier)
        #expect(context.hasAccessToPrivateData)
        #expect(manager.store.state(for: context.uniqueIdentifier)?.hasAccessToPrivateData == true)
        tab.reload()
        #expect(try await marker(of: tab, expecting: "1") == "1")
    }

    @Test func `an extension opens a tab in the browser window`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let model = WindowModel(session: session, defaults: nil)
        let manager = TestExtension.manager()
        manager.windows.windowDidAppear(model, window: nil)
        manager.windows.update()
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await TestExtension.waitForBackground(of: context)
        try await withProfileStore { store in
            // The requesting page must be a tab known to the extension: otherwise WebKit rejects its messages.
            let configuration = TestPages.configuration()
            configuration.websiteDataStore = store
            manager.attach(to: configuration)
            let tabManager = model.space.tabManager
            let opener = tabManager.insertTab(configuration: configuration, after: nil, select: true)
            manager.windows.update()
            var components = try #require(URLComponents(url: TestPages.url("opener"), resolvingAgainstBaseURL: false))
            components.fragment = "matcha-open-tab"
            try opener.load(#require(components.url))
            // Service worker's reply, which the content script writes into the page (“created <id>” or the error).
            var reply = ""
            for _ in 0 ..< 600 {
                reply = await (try? opener.loadedWebView.evaluateJavaScript("document.body?.dataset.reply ?? ''") as? String) ?? ""
                if tabManager.tabs.count > 1 || reply.hasPrefix("error") {
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(!reply.hasPrefix("error"), "\(reply)")
            #expect(tabManager.tabs.count == 2, "\(tabManager.tabs.count) onglets, réponse : \(reply)")
            let created = try #require(tabManager.tabs.first { $0 !== opener })
            try await waitUntil { created.url != nil }
            #expect(created.url == URL(string: "about:blank"))
            #expect(tabManager.selectedTab === opener)
            #expect(manager.windows.adapter(for: created) != nil)
            opener.unload(resettingTo: nil, title: nil)
        }
    }

    // MARK: Decisions

    @Test func `permission requests ask the user and grant nothing on refusal`() async throws {
        let prompter = FakePermissionPrompter(answer: false)
        let manager = TestExtension.manager(prompter: prompter)
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        let requested: Set<WKWebExtension.Permission> = [.cookies, .storage]
        let refused = await withCheckedContinuation { continuation in
            manager.webExtensionController(manager.controller, promptForPermissions: requested, in: nil, for: context) { allowed, _ in
                continuation.resume(returning: allowed)
            }
        }
        #expect(refused.isEmpty)
        #expect(prompter.requests.last?.permissions == ["cookies", "storage"])
        #expect(prompter.requests.last?.extensionName == "Matcha Test Extension")

        prompter.answer = true
        let urls: Set<URL> = try [#require(URL(string: "https://example.com/a"))]
        let allowed = await withCheckedContinuation { continuation in
            manager.webExtensionController(manager.controller, promptForPermissionToAccess: urls, in: nil, for: context) { allowed, _ in
                continuation.resume(returning: allowed)
            }
        }
        #expect(allowed == urls)
        #expect(prompter.requests.last?.websites == ["example.com"])
    }

    /// Audit E5: a refusal holds for a day, one request at a time, and a website given can be taken back.
    @Test func `a refusal is remembered and an extension can't pile up requests`() async throws {
        let prompter = HeldPermissionPrompter()
        let manager = TestExtension.manager(prompter: prompter)
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        let answers = Answers()
        manager.webExtensionController(manager.controller, promptForPermissions: [.cookies], in: nil, for: context) { allowed, _ in
            MainActor.assumeIsolated { answers.values.append(allowed) }
        }
        // A second request while the first waits: refused without being shown.
        manager.webExtensionController(manager.controller, promptForPermissions: [.storage], in: nil, for: context) { allowed, _ in
            MainActor.assumeIsolated { answers.values.append(allowed) }
        }
        #expect(prompter.pending.count == 1)
        #expect(answers.values == [[]])

        prompter.answer(false)
        #expect(answers.values == [[], []])
        #expect(context.permissionStatus(for: .cookies) == .deniedExplicitly)
        let expiration = try #require(context.deniedPermissions[.cookies])
        #expect(abs(expiration.timeIntervalSinceNow - ExtensionPromptPolicy.denialDuration) < 60)

        // A website given, then taken back in Settings.
        let pattern = try WKWebExtension.MatchPattern(string: "*://*.example.com/*")
        context.setPermissionStatus(.grantedExplicitly, for: pattern)
        manager.revokeSite(pattern.string, identifier: context.uniqueIdentifier)
        #expect(context.permissionStatus(for: pattern) != .grantedExplicitly)
        #expect(manager.store.state(for: context.uniqueIdentifier)?.grantedMatchPatterns[pattern.string] == nil)
    }

    @Test func `decisions are restored at the next load`() async throws {
        let manager = TestExtension.manager()
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        context.setPermissionStatus(.grantedExplicitly, for: .tabs)
        let identifier = context.uniqueIdentifier
        try await waitUntil { manager.store.state(for: identifier)?.grantedPermissions["tabs"] != nil }
        manager.unload(identifier: identifier)

        let reloaded = try await manager.load(resourceBaseURL: folder, identifier: identifier)
        #expect(reloaded !== context)
        #expect(reloaded.hasPermission(.tabs))
        #expect(reloaded.currentPermissionMatchPatterns.contains { $0.string == "obtest://*/*" })
    }

    @Test func `installed extensions load at start, unless disabled`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Extensions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = TestExtension.uniqueIdentifier("first")
        let second = TestExtension.uniqueIdentifier("second")
        _ = try TestExtension.makeFolder(in: directory, named: first)
        _ = try TestExtension.makeFolder(in: directory, named: second)
        let manager = TestExtension.manager(directory: directory)
        var disabled = ExtensionState()
        disabled.isEnabled = false
        manager.store.setState(disabled, for: second)
        manager.start()
        try await waitUntil { manager.contexts[first] != nil }
        #expect(manager.contexts[second] == nil)

        try await manager.setEnabled(true, identifier: second)
        #expect(manager.contexts[second]?.isLoaded == true)
        try await manager.setEnabled(false, identifier: first)
        #expect(manager.contexts[first] == nil)
        #expect(manager.store.state(for: first)?.isEnabled == false)
    }
}

/// Answers WebKit received, in order.
@MainActor
private final class Answers {
    var values: [Set<WKWebExtension.Permission>] = []
}
