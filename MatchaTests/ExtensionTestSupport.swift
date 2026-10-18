import Foundation
@testable import Matcha
import Testing
import WebKit

/// Contrôleur d'extensions factice : il note les événements reçus, avec les identifiants des onglets et des fenêtres.
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

    /// Événements reçus depuis le dernier appel.
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
            Issue.record("Fenêtre inattendue : \(window)")
            return UUID()
        }
        return window.windowID
    }

    private static func id(of tab: any WKWebExtensionTab) -> UUID {
        guard let tab = tab as? ExtensionTab else {
            Issue.record("Onglet inattendu : \(tab)")
            return UUID()
        }
        return tab.tabID
    }
}

/// Réponses données d'avance aux demandes de permissions ; note les demandes.
@MainActor
final class FakePermissionPrompter: ExtensionPermissionPrompting {
    var answer: Bool
    private(set) var requests: [ExtensionPermissionRequest] = []

    init(answer: Bool) {
        self.answer = answer
    }

    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (Bool) -> Void) {
        requests.append(request)
        completion(answer)
    }
}

/// L'extension d'essai (`Fixtures/test-extension-*`, Manifest V3) : un script de contenu qui marque les pages `obtest:`
/// (`document.body.dataset.matchaExtension = "1"`) et demande un onglet au service worker sur une page `#matcha-open-tab`.
@MainActor
enum TestExtension {
    /// Copie de l'extension dans un dossier temporaire neuf (à effacer après le test), sous ses noms de fichiers réels.
    static func makeFolder(in parent: URL? = nil, named name: String = "TestExtension-\(UUID().uuidString)") throws -> URL {
        // Les motifs `obtest://*/*` du manifeste ne se lisent qu'une fois le schéma déclaré.
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

    /// Identifiant neuf : deux contrôleurs (tests en parallèle) qui chargent le même identifiant partagent le monde
    /// JavaScript des scripts de contenu (`WebExtension-<identifiant>`), et les messages d'une page peuvent partir vers
    /// l'extension de l'autre test.
    static func uniqueIdentifier(_ prefix: String = "matcha-test") -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    /// Gestionnaire de test : contrôleur non persistant, rien d'enregistré, dossier d'extensions donné (nil : aucun).
    static func manager(
        directory: URL? = nil,
        prompter: FakePermissionPrompter = FakePermissionPrompter(answer: false),
    ) -> ExtensionManager {
        let manager = ExtensionManager(configuration: .nonPersistent(), store: ExtensionStateStore(defaults: nil), directory: directory)
        manager.permissionPrompter = prompter
        return manager
    }

    /// Extension d'essai chargée dans `manager`, avec ses sites accordés (`obtest://*/*`).
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

    /// Attend que l'arrière-plan de l'extension soit chargé : ses scripts de contenu sont alors posés sur les pages.
    /// Borné par `waitUntil` : une réponse qui ne vient jamais fait échouer le test au lieu de bloquer la suite.
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

    /// Réponse de `loadBackgroundContent`.
    private final class BackgroundLoad {
        private(set) var isFinished = false
        private(set) var error: (any Error)?

        func finish(_ error: (any Error)?) {
            isFinished = true
            self.error = error
        }
    }

    /// Marque posée par le script de contenu dans la page de `webView` : « 1 », sinon « none ».
    static func marker(in webView: WKWebView) async -> String? {
        try? await webView.evaluateJavaScript("document.body ? (document.body.dataset.matchaExtension || 'none') : 'none'") as? String
    }
}
