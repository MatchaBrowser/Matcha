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

    /// Instance de l'app ; dans l'app hôte des tests unitaires, un contrôleur non persistant, sans rien d'enregistré
    /// ni de chargé.
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
    /// Change à chaque mise à jour d'une action (icône, titre, badge) : les boutons de la tâche 6.5 le suivront.
    private(set) var actionRevision = 0
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

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
    }

    private static func makeShared() -> ExtensionManager {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
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

    /// Charge, en tâche de fond, les extensions actives du dossier des extensions. Sans effet au second appel.
    func start() {
        guard !isStarted, let directory else {
            return
        }
        isStarted = true
        let enabled = ExtensionInstallDirectory.installedExtensions(in: directory)
            .filter { store.state(for: $0.identifier)?.isEnabled ?? true }
        Task {
            for (identifier, url) in enabled {
                do {
                    try await load(resourceBaseURL: url, identifier: identifier)
                } catch {
                    Logger.extensions.error("Extension non chargée : \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Charge l'extension du dossier `url` (décompressé, avec son `manifest.json`) sous l'identifiant `identifier`, avec
    /// les décisions retenues pour lui ; elle est désormais active.
    @discardableResult
    func load(resourceBaseURL url: URL, identifier: String) async throws -> WKWebExtensionContext {
        guard ExtensionInstallDirectory.isValidIdentifier(identifier) else {
            throw ExtensionError.invalidIdentifier(identifier)
        }
        guard contexts[identifier] == nil else {
            throw ExtensionError.alreadyLoaded(identifier)
        }
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        // Un autre chargement du même identifiant a pu aboutir pendant la lecture.
        guard contexts[identifier] == nil else {
            throw ExtensionError.alreadyLoaded(identifier)
        }
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = identifier
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
        store.setState(ExtensionState(context: context, isEnabled: true), for: identifier)
        let errors = webExtension.errors.count
        Logger.extensions.info("Extension chargée (\(identifier, privacy: .public), \(errors, privacy: .public) erreur(s) du manifeste)")
        return context
    }

    /// Décharge l'extension `identifier` (ses décisions sont retenues).
    func unload(identifier: String) {
        guard let context = contexts.removeValue(forKey: identifier) else {
            return
        }
        saveState(of: context)
        do {
            try controller.unload(context)
            Logger.extensions.info("Extension déchargée (\(identifier, privacy: .public))")
        } catch {
            Logger.extensions.error("Extension non déchargée : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Active ou désactive l'extension installée `identifier` : elle est chargée depuis le dossier des extensions, ou
    /// déchargée ; retenu pour les prochains lancements.
    func setEnabled(_ isEnabled: Bool, identifier: String) async throws {
        if isEnabled, contexts[identifier] == nil, let directory {
            try await load(resourceBaseURL: directory.appendingPathComponent(identifier, isDirectory: true), identifier: identifier)
        } else if !isEnabled {
            unload(identifier: identifier)
        }
        var state = store.state(for: identifier) ?? ExtensionState()
        state.isEnabled = isEnabled
        store.setState(state, for: identifier)
    }

    // MARK: Décisions

    /// Ouvre (ou ferme) les fenêtres privées à l'extension `identifier` : choix de l'utilisateur seulement (tâche 6.4) ;
    /// retenu, et appliqué tout de suite si elle est chargée.
    func setAccessToPrivateData(_ isAllowed: Bool, identifier: String) {
        if let context = contexts[identifier] {
            context.hasAccessToPrivateData = isAllowed
            saveState(of: context)
        } else {
            var state = store.state(for: identifier) ?? ExtensionState()
            state.hasAccessToPrivateData = isAllowed
            store.setState(state, for: identifier)
        }
    }

    /// Retient les décisions actuelles de `context` (permissions, sites, fenêtres privées).
    func saveState(of context: WKWebExtensionContext) {
        let identifier = context.uniqueIdentifier
        guard contexts[identifier] === context || store.state(for: identifier) != nil else {
            return
        }
        let isEnabled = store.state(for: identifier)?.isEnabled ?? true
        store.setState(ExtensionState(context: context, isEnabled: isEnabled), for: identifier)
    }

    /// Retient les décisions de toutes les extensions chargées.
    func saveAllStates() {
        contexts.values.forEach(saveState(of:))
    }

    /// Une action a changé (tâche 6.5 : boutons des extensions).
    func actionDidUpdate() {
        actionRevision &+= 1
    }

    /// Décisions retenues dès que WebKit les change (réponse à une demande, `permissions.remove()`…), et à la fermeture
    /// de l'app.
    private func observeContexts() {
        let names: [Notification.Name] = [
            WKWebExtensionContext.permissionsWereGrantedNotification,
            WKWebExtensionContext.permissionsWereDeniedNotification,
            WKWebExtensionContext.grantedPermissionsWereRemovedNotification,
            WKWebExtensionContext.deniedPermissionsWereRemovedNotification,
            WKWebExtensionContext.permissionMatchPatternsWereGrantedNotification,
            WKWebExtensionContext.permissionMatchPatternsWereDeniedNotification,
            WKWebExtensionContext.grantedPermissionMatchPatternsWereRemovedNotification,
            WKWebExtensionContext.deniedPermissionMatchPatternsWereRemovedNotification,
        ]
        // Toutes les extensions chargées sont relues (rien n'est écrit pour celles qui n'ont pas changé) : la
        // notification ne traverse pas la frontière d'isolation.
        for name in names + [NSApplication.willTerminateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveAllStates()
                }
            })
        }
    }
}
