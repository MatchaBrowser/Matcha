import AppKit
import Observation
import OSLog
import WebKit

/// Extensions web de l'app (tâche 6.3) : un seul `WKWebExtensionController`, branché sur la configuration de toutes les
/// pages (`WebConfigurationFactory`), fenêtres privées comprises ; les extensions n'y voient et n'y injectent rien tant
/// qu'elles n'ont pas l'accès aux données privées (`hasAccessToPrivateData`, refusé par défaut, comme dans Safari).
///
/// - Chargement : `load(resourceBaseURL:identifier:)` (dossier décompressé) ; au lancement (`start`), les extensions
///   actives de `Application Support/Extensions/<identifiant>/` (`ExtensionInstallDirectory`). L'identifiant fixe
///   l'adresse des pages de l'extension (`webkit-extension://<identifiant>/`) et son stockage, gardés d'un lancement à
///   l'autre (contrôleur persistant, `.default()`).
/// - Décisions de l'utilisateur (permissions, sites, fenêtres privées) : retenues par `ExtensionStateStore`, remises à
///   chaque chargement ; jamais rien d'accordé sans lui.
/// - Fenêtres et onglets : `ExtensionWindows` ; délégué du contrôleur : `+Delegate`.
@MainActor
@Observable
final class ExtensionManager: NSObject {
    /// Schéma des pages des extensions (options, popup, arrière-plan).
    nonisolated static let scheme = "webkit-extension"

    /// Instance de l'app ; dans l'app hôte des tests unitaires et avec une base de test (tests d'interface), un
    /// contrôleur non persistant, sans rien d'enregistré ni de chargé.
    static let shared = ExtensionManager.makeShared()

    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored let windows = ExtensionWindows()
    @ObservationIgnored let store: ExtensionStateStore
    /// Dossier des extensions installées ; nil (tests) : aucun chargement au lancement.
    @ObservationIgnored let directory: URL?
    /// Demande à l'utilisateur ce qu'une extension réclame (remplacé dans les tests).
    @ObservationIgnored var permissionPrompter: any ExtensionPermissionPrompting = ExtensionPermissionAlert()
    /// Bulles des actions des extensions ; la tâche 6.5 les ancrera à leur bouton.
    @ObservationIgnored let popups = ExtensionPopupPresenter()
    /// Extensions chargées, par identifiant.
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// Extensions installées, chargées ou non, par identifiant (tâche 6.4) : de quoi les montrer dans les réglages.
    private(set) var installed: [String: WKWebExtension] = [:]
    /// Change à chaque mise à jour d'une action (icône, titre, badge) : les boutons la suivent (tâche 6.5).
    private(set) var actionRevision = 0
    /// Change quand les boutons à montrer changent (bouton masqué ou affiché, fenêtres privées ; tâche 6.5).
    private(set) var buttonsRevision = 0
    /// Boutons des extensions affichés, pour y ancrer leur bulle (tâche 6.5).
    @ObservationIgnored let buttonAnchors = ExtensionButtonAnchors()
    /// Réponses aux messages natifs (refusés), espacées par extension.
    @ObservationIgnored var nativeMessages = NativeMessageThrottle()
    /// Extensions dont un message natif a déjà été refusé (une ligne de journal chacune).
    @ObservationIgnored var nativeMessageSenders: Set<String> = []
    @ObservationIgnored var isStarted = false
    @ObservationIgnored var observers: [any NSObjectProtocol] = []

    init(configuration: WKWebExtensionController.Configuration, store: ExtensionStateStore, directory: URL?) {
        // Pages des extensions (popup, options, arrière-plan) : présentées aux sites comme Safari, comme les onglets.
        let pages = WKWebViewConfiguration()
        pages.applicationNameForUserAgent = WebConfigurationFactory.applicationNameForUserAgent
        configuration.webViewConfiguration = pages
        controller = WKWebExtensionController(configuration: configuration)
        self.store = store
        self.directory = directory
        super.init()
        controller.delegate = self
        windows.sink = controller
        observeContexts()
        // Bulle d'une action sous le bouton de son extension (dans la fenêtre et, s'il y en a plusieurs, la carte de
        // l'onglet visé), sinon au coin haut droit de la fenêtre.
        popups.anchor = { [weak self] action, window in
            guard let self, let context = action.webExtensionContext, let identifier = identifier(of: context),
                  let view = buttonAnchors.view(for: identifier, tabID: (action.associatedTab as? ExtensionTab)?.tabID, in: window)
            else {
                return ExtensionPopupPresenter.topTrailingAnchor(in: window)
            }
            return (view, view.bounds)
        }
    }

    private static func makeShared() -> ExtensionManager {
        // App hôte des tests unitaires, et base de test (tests d'interface) : rien de l'utilisateur n'est lu ni écrit
        // (mêmes réglages et même conteneur que l'app).
        let isUnitTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard !isUnitTesting, !UserDefaults.standard.bool(forKey: BrowserSession.inMemoryStoreKey) else {
            return ExtensionManager(configuration: .nonPersistent(), store: ExtensionStateStore(defaults: nil), directory: nil)
        }
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return ExtensionManager(
            configuration: .default(),
            store: ExtensionStateStore(defaults: .standard),
            directory: applicationSupport.map(ExtensionInstallDirectory.directory(in:)),
        )
    }

    /// Vrai pour une adresse de page d'extension.
    nonisolated static func isExtensionURL(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == scheme
    }

    /// Branche les extensions sur une configuration de pages (`WebConfigurationFactory`).
    func attach(to configuration: WKWebViewConfiguration) {
        configuration.webExtensionController = controller
    }

    /// Extension dont `url` est une page, si elle est chargée.
    func context(for url: URL) -> WKWebExtensionContext? {
        controller.extensionContext(for: url)
    }

    // MARK: Chargement

    /// Lit l'extension installée `identifier` (dossier des extensions ou `.appex` d'une app), sans la charger ; elle
    /// rejoint `installed`.
    @discardableResult
    func read(_ identifier: String) async throws -> WKWebExtension {
        let webExtension: WKWebExtension
        if let path = store.state(for: identifier)?.appExtensionPath {
            guard let bundle = Bundle(url: URL(filePath: path)) else {
                throw ExtensionError.notInstalled(identifier)
            }
            webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        } else if let directory {
            webExtension = try await WKWebExtension(resourceBaseURL: directory.appendingPathComponent(identifier, isDirectory: true))
        } else {
            throw ExtensionError.notInstalled(identifier)
        }
        installed[identifier] = webExtension
        return webExtension
    }

    /// Charge l'extension du dossier `url` (décompressé, avec son `manifest.json`) sous l'identifiant `identifier`, avec
    /// les décisions retenues pour lui ; elle est désormais active.
    @discardableResult
    func load(resourceBaseURL url: URL, identifier: String) async throws -> WKWebExtensionContext {
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        return try load(webExtension, identifier: identifier)
    }

    /// Charge `webExtension` sous l'identifiant `identifier`, avec les décisions retenues pour lui ; elle est désormais
    /// active.
    @discardableResult
    func load(_ webExtension: WKWebExtension, identifier: String) throws -> WKWebExtensionContext {
        guard ExtensionInstallDirectory.isValidIdentifier(identifier) else {
            throw ExtensionError.invalidIdentifier(identifier)
        }
        guard contexts[identifier] == nil else {
            throw ExtensionError.alreadyLoaded(identifier)
        }
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = webExtensionIdentifier(for: identifier)
        if let baseURL = URL(string: "\(Self.scheme)://\(identifier)/") {
            context.baseURL = baseURL
        }
        #if DEBUG
            context.isInspectable = true
        #endif
        (store.state(for: identifier) ?? ExtensionState()).apply(to: context)
        // WebKit demande les fenêtres ouvertes pendant le chargement : elles doivent être à jour.
        windows.update()
        try controller.load(context)
        contexts[identifier] = context
        installed[identifier] = webExtension
        store.setState(state(of: context, identifier: identifier, isEnabled: true), for: identifier)
        let errors = webExtension.errors.count
        Logger.extensions.info("Extension chargée (\(identifier, privacy: .public), \(errors, privacy: .public) erreur(s) du manifeste)")
        return context
    }

    /// Décharge l'extension `identifier` (ses décisions sont retenues).
    func unload(identifier: String) {
        guard let context = contexts.removeValue(forKey: identifier) else {
            return
        }
        saveState(of: context, identifier: identifier)
        do {
            try controller.unload(context)
            Logger.extensions.info("Extension déchargée (\(identifier, privacy: .public))")
        } catch {
            Logger.extensions.error("Extension non déchargée : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Oublie l'extension désinstallée `identifier` (`+Installed`).
    func forget(_ identifier: String) {
        installed[identifier] = nil
    }

    /// Une action a changé (tâche 6.5 : boutons des extensions).
    func actionDidUpdate() {
        actionRevision &+= 1
    }

    /// Les boutons à montrer ont changé (tâche 6.5).
    func buttonsDidChange() {
        buttonsRevision &+= 1
    }
}
