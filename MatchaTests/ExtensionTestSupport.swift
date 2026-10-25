import Foundation
@testable import Matcha
import Testing
import WebKit

/// Fake extension controller: it records the events received, with the identifiers of the tabs and windows.
@MainActor
final class FakeExtensionSink: ExtensionEventSink {
    enum Event: Equatable {
        case openWindow(UUID)
        case closeWindow(UUID)
        case focusWindow(UUID?)
        case openTab(UUID)
        case closeTab(UUID, windowIsClosing: Bool)
        case activateTab(UUID, previous: UUID?)
        case selectTabs([UUID])
        case deselectTabs([UUID])
        case moveTab(UUID, from: Int, window: UUID?)
        case changeTab(UUID, WKWebExtension.TabChangedProperties)
    }

    var isListening = true
    private(set) var events: [Event] = []

    /// Events received since the last call.
    func take() -> [Event] {
        defer { events = [] }
        return events
    }

    func didOpenWindow(_ newWindow: any WKWebExtensionWindow) {
        events.append(.openWindow(Self.id(of: newWindow)))
    }

    func didCloseWindow(_ closedWindow: any WKWebExtensionWindow) {
        events.append(.closeWindow(Self.id(of: closedWindow)))
    }

    func didFocusWindow(_ focusedWindow: (any WKWebExtensionWindow)?) {
        events.append(.focusWindow(focusedWindow.map(Self.id(of:))))
    }

    func didOpenTab(_ newTab: any WKWebExtensionTab) {
        events.append(.openTab(Self.id(of: newTab)))
    }

    func didCloseTab(_ closedTab: any WKWebExtensionTab, windowIsClosing: Bool) {
        events.append(.closeTab(Self.id(of: closedTab), windowIsClosing: windowIsClosing))
    }

    func didActivateTab(_ activatedTab: any WKWebExtensionTab, previousActiveTab previousTab: (any WKWebExtensionTab)?) {
        events.append(.activateTab(Self.id(of: activatedTab), previous: previousTab.map(Self.id(of:))))
    }

    func didSelectTabs(_ selectedTabs: [any WKWebExtensionTab]) {
        events.append(.selectTabs(selectedTabs.map(Self.id(of:))))
    }

    func didDeselectTabs(_ deselectedTabs: [any WKWebExtensionTab]) {
        events.append(.deselectTabs(deselectedTabs.map(Self.id(of:))))
    }

    func didMoveTab(_ movedTab: any WKWebExtensionTab, from index: Int, in oldWindow: (any WKWebExtensionWindow)?) {
        events.append(.moveTab(Self.id(of: movedTab), from: index, window: oldWindow.map(Self.id(of:))))
    }

    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for changedTab: any WKWebExtensionTab) {
        events.append(.changeTab(Self.id(of: changedTab), properties))
    }

    private static func id(of window: any WKWebExtensionWindow) -> UUID {
        guard let window = window as? ExtensionWindow else {
            Issue.record("Unexpected window: \(window)")
            return UUID()
        }
        return window.windowID
    }

    private static func id(of tab: any WKWebExtensionTab) -> UUID {
        guard let tab = tab as? ExtensionTab else {
            Issue.record("Unexpected tab: \(tab)")
            return UUID()
        }
        return tab.tabID
    }
}

/// Answers given in advance to permission requests; records the requests.
@MainActor
final class FakePermissionPrompter: ExtensionPermissionPrompting {
    var answer: Bool
    private(set) var requests: [ExtensionPermissionRequest] = []

    init(answer: Bool) {
        self.answer = answer
    }

    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (ExtensionPermissionAnswer) -> Void) {
        requests.append(request)
        completion(answer ? .allowed : .denied)
    }
}

/// Holds each request until the test answers it.
@MainActor
final class HeldPermissionPrompter: ExtensionPermissionPrompting {
    private(set) var pending: [(ExtensionPermissionRequest, @MainActor (ExtensionPermissionAnswer) -> Void)] = []

    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (ExtensionPermissionAnswer) -> Void) {
        pending.append((request, completion))
    }

    func answer(_ allowed: Bool) {
        answer(allowed ? .allowed : .denied)
    }

    func answer(_ answer: ExtensionPermissionAnswer) {
        let first = pending.removeFirst()
        first.1(answer)
    }
}

/// The test extension (`Fixtures/test-extension-*`, Manifest V3): a content script that marks `obtest:` pages
/// (`document.body.dataset.matchaExtension = "1"`) and asks the service worker for a tab on a `#matcha-open-tab` page.
@MainActor
enum TestExtension {
    /// Copy of the extension in a new temporary folder (to delete after the test), under its real file names.
    static func makeFolder(in parent: URL? = nil, named name: String = "TestExtension-\(UUID().uuidString)") throws -> URL {
        // The `obtest://*/*` patterns of the manifest can only be read once the scheme is declared.
        WKWebExtension.MatchPattern.registerCustomURLScheme(TestPages.scheme)
        let bundle = Bundle(for: TestPages.self)
        let folder = (parent ?? FileManager.default.temporaryDirectory).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = [
            ("test-extension-manifest.json", ExtensionInstallDirectory.manifestName),
            ("test-extension-content.js", "test-extension-content.js"),
            ("test-extension-background.js", "test-extension-background.js"),
        ]
        for (source, target) in files {
            let url = try #require(bundle.url(forResource: source, withExtension: nil))
            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(target))
        }
        return folder
    }

    /// New identifier: two controllers (tests in parallel) that load the same identifier share the JavaScript world
    /// of the content scripts (`WebExtension-<identifier>`), and the messages of a page can go to the other test's
    /// extension.
    static func uniqueIdentifier(_ prefix: String = "matcha-test") -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    /// Test manager: non-persistent controller, nothing saved, given extensions folder (nil: none).
    static func manager(
        directory: URL? = nil,
        prompter: any ExtensionPermissionPrompting = FakePermissionPrompter(answer: false),
    ) -> ExtensionManager {
        let manager = ExtensionManager(configuration: .nonPersistent(), store: ExtensionStateStore(defaults: nil), directory: directory)
        manager.permissionPrompter = prompter
        // Its windows, as the app gives them (`AppEnvironment`).
        let windows = ExtensionWindows(sink: manager.controller)
        windows.manager = manager
        manager.host = windows
        return manager
    }

    /// Test extension loaded in `manager`, with its granted sites (`obtest://*/*`).
    static func load(
        in manager: ExtensionManager,
        identifier: String = TestExtension.uniqueIdentifier(),
    ) async throws -> (context: WKWebExtensionContext, folder: URL) {
        let folder = try makeFolder()
        let context = try await manager.load(resourceBaseURL: folder, identifier: identifier)
        for pattern in context.webExtension.requestedPermissionMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        return (context, folder)
    }

    /// Waits until the extension's background has loaded: its content scripts are then injected into the pages.
    /// Bounded by `waitUntil`: a reply that never comes makes the test fail instead of blocking the rest of the suite.
    static func waitForBackground(of context: WKWebExtensionContext) async throws {
        let load = BackgroundLoad()
        Task {
            do {
                try await context.loadBackgroundContent()
                load.finish(nil)
            } catch {
                load.finish(error)
            }
        }
        try await waitUntil { load.isFinished }
        if let error = load.error {
            throw error
        }
    }

    /// Reply from `loadBackgroundContent`.
    private final class BackgroundLoad {
        private(set) var isFinished = false
        private(set) var error: (any Error)?

        func finish(_ error: (any Error)?) {
            isFinished = true
            self.error = error
        }
    }

    /// Mark set by the content script in the page of `webView`: “1”, otherwise “none”.
    static func marker(in webView: WKWebView) async -> String? {
        try? await webView.evaluateJavaScript("document.body ? (document.body.dataset.matchaExtension || 'none') : 'none'") as? String
    }
}

extension ExtensionManager {
    /// The windows of a test manager (`TestExtension.manager`).
    var testWindows: ExtensionWindows {
        guard let windows = host as? ExtensionWindows else {
            preconditionFailure("Manager made without its windows")
        }
        return windows
    }
}

extension ExtensionManager {
    /// Loads the extension of folder `url` (unpacked, with its `manifest.json`) under identifier `identifier`, with the
    /// decisions remembered for it, without installing it (tests only, review EX26).
    @discardableResult
    func load(resourceBaseURL url: URL, identifier: String) async throws -> WKWebExtensionContext {
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        return try load(webExtension, identifier: identifier)
    }
}

extension ExtensionStateStore {
    /// Known identifiers (tests only, review EX26).
    var identifiers: [String] {
        states.keys.sorted()
    }
}

/// A flag set from a `@Sendable` closure (observation's `onChange`).
final class SendableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool {
        lock.withLock { raised }
    }

    func raise() {
        lock.withLock { raised = true }
    }
}
