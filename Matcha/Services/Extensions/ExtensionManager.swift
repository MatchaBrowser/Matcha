import AppKit
import Observation
import OSLog
import WebKit

/// The app's web extensions (task 6.3): a single `WKWebExtensionController`, plugged into the configuration of all
/// pages (`WebConfigurationFactory`), private windows included; extensions see and inject nothing there as long as they
/// do not have access to private data (`hasAccessToPrivateData`, denied by default, as in Safari).
///
/// - Loading: `load(resourceBaseURL:identifier:)` (unpacked folder); at launch (`start`), the enabled extensions of
///   `Application Support/Extensions/<identifier>/` (`ExtensionInstallDirectory`). The identifier sets the address of
///   the extension's pages (`webkit-extension://<identifier>/`) and its storage, kept from one launch to the next
///   (persistent controller, `.default()`).
/// - User decisions (permissions, websites, private windows): remembered by `ExtensionStateStore`, restored at each
///   load; nothing is ever granted without the user.
/// - Windows and tabs: `ExtensionWindows`; controller delegate: `+Delegate`.
@MainActor
@Observable
final class ExtensionManager: NSObject {
    /// Scheme of the extension pages (options, popup, background).
    nonisolated static let scheme = "webkit-extension"

    /// The app's instance; in the unit tests' host app and with a test store (UI tests), a non-persistent controller,
    /// with nothing saved or loaded.
    static let shared = ExtensionManager.makeShared()

    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored let windows = ExtensionWindows()
    @ObservationIgnored let store: ExtensionStateStore
    /// Folder of the installed extensions; nil (tests): nothing loaded at launch.
    @ObservationIgnored let directory: URL?
    /// Asks the user what an extension requests (replaced in the tests).
    @ObservationIgnored var permissionPrompter: any ExtensionPermissionPrompting = ExtensionPermissionAlert()
    /// Extensions whose request waits for the user: one at a time each (audit E5).
    @ObservationIgnored var promptingContexts: Set<ObjectIdentifier> = []
    /// Popovers of the extensions' actions, anchored to their button (`popups.anchor`).
    @ObservationIgnored let popups = ExtensionPopupPresenter()
    /// Loaded extensions, by identifier.
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// Installed extensions, loaded or not, by identifier (task 6.4): what is needed to show them in the settings.
    private(set) var installed: [String: WKWebExtension] = [:]
    /// Folders of `directory`, read at creation and after each installation or removal: never from a view (audit C7).
    private(set) var installedFolders: [String] = []
    /// Changes at each update of an action (icon, title, badge): the buttons follow it (task 6.5).
    private(set) var actionRevision = 0
    /// Changes when the buttons to show change (button hidden or shown, private windows; task 6.5).
    private(set) var buttonsRevision = 0
    /// Displayed extension buttons, to anchor their popover to them (task 6.5).
    @ObservationIgnored let buttonAnchors = ExtensionButtonAnchors()
    /// Answers to native messages (refused), spaced out per extension.
    @ObservationIgnored var nativeMessages = NativeMessageThrottle()
    /// Extensions that already had a native message refused (one log line each).
    @ObservationIgnored var nativeMessageSenders: Set<String> = []
    @ObservationIgnored var isStarted = false
    @ObservationIgnored var observers: [any NSObjectProtocol] = []

    init(configuration: WKWebExtensionController.Configuration, store: ExtensionStateStore, directory: URL?) {
        // Extension pages (popup, options, background): presented to websites as Safari, like the tabs.
        let pages = WKWebViewConfiguration()
        pages.applicationNameForUserAgent = WebConfigurationFactory.applicationNameForUserAgent
        WebInspection.apply(to: pages.preferences)
        configuration.webViewConfiguration = pages
        controller = WKWebExtensionController(configuration: configuration)
        self.store = store
        self.directory = directory
        super.init()
        refreshInstalledFolders()
        controller.delegate = self
        windows.sink = controller
        observeContexts()
        // Developer tools: extension pages inspectable (Safari > Develop) depending on the setting.
        observers
            .append(NotificationCenter.default.addObserver(forName: WebInspection.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.contexts.values.forEach { $0.isInspectable = WebInspection.isEnabled() }
                }
            })
        // An action's popover below its extension's button (in the window and, if there are several, the card of the
        // targeted tab), otherwise at the top right corner of the window.
        popups.anchor = { [weak self] action, window in
            guard let self, let context = action.webExtensionContext, let identifier = identifier(of: context),
                  let view = buttonAnchors.view(for: identifier, tabID: (action.associatedTab as? ExtensionTab)?.tabID, in: window)
            else {
                return ExtensionPopupPresenter.topTrailingAnchor(in: window)
            }
            return (view, view.bounds)
        }
    }

    /// A manager that goes away (tests) takes its observers with it (audit C7).
    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private static func makeShared() -> ExtensionManager {
        // Host app of the unit tests, and test store (UI tests): nothing of the user's is read or written (same
        // settings and same container as the app).
        guard !TestEnvironment.usesInMemoryStore() else {
            return ExtensionManager(configuration: .nonPersistent(), store: ExtensionStateStore(defaults: nil), directory: nil)
        }
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return ExtensionManager(
            configuration: .default(),
            store: ExtensionStateStore(defaults: .standard),
            directory: applicationSupport.map(ExtensionInstallDirectory.directory(in:)),
        )
    }

    /// True for the address of an extension page.
    nonisolated static func isExtensionURL(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == scheme
    }

    /// Plugs the extensions into a page configuration (`WebConfigurationFactory`).
    func attach(to configuration: WKWebViewConfiguration) {
        configuration.webExtensionController = controller
    }

    /// Extension of which `url` is a page, if it is loaded.
    func context(for url: URL) -> WKWebExtensionContext? {
        controller.extensionContext(for: url)
    }

    // MARK: Loading

    /// Reads the installed extension `identifier` (extensions folder or an app's `.appex`) without loading it; it joins
    /// `installed`.
    @discardableResult
    func read(_ identifier: String) async throws -> WKWebExtension {
        let webExtension: WKWebExtension
        if let state = store.state(for: identifier), let path = state.appExtensionPath {
            let url = URL(filePath: path)
            guard let bundle = Bundle(url: url) else {
                throw ExtensionError.notInstalled(identifier)
            }
            // Another bundle at the same place (other identifier, other team, altered signature): not loaded.
            if let identity = state.appExtensionIdentity, SafariExtensionFinder.safariIdentifier(ofAppExtensionAt: url) != identity {
                throw ExtensionError.identityChanged(identifier)
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

    /// Loads the extension of folder `url` (unpacked, with its `manifest.json`) under identifier `identifier`, with the
    /// decisions remembered for it; it is now enabled.
    @discardableResult
    func load(resourceBaseURL url: URL, identifier: String) async throws -> WKWebExtensionContext {
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        return try load(webExtension, identifier: identifier)
    }

    /// Reads the extensions folder again: at launch, after an installation or a removal.
    func refreshInstalledFolders() {
        installedFolders = directory.map { ExtensionInstallDirectory.installedExtensions(in: $0).map(\.identifier) } ?? []
    }

    /// Loads `webExtension` under identifier `identifier`, with the decisions remembered for it; it is now enabled.
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
        context.isInspectable = WebInspection.isEnabled()
        (store.state(for: identifier) ?? ExtensionState()).apply(to: context)
        // WebKit asks for the open windows during loading: they must be up to date.
        windows.update(beforeLoading: true)
        try controller.load(context)
        contexts[identifier] = context
        installed[identifier] = webExtension
        store.setState(state(of: context, identifier: identifier, isEnabled: true), for: identifier)
        let errors = webExtension.errors.count
        Logger.extensions.info("Extension loaded (\(identifier, privacy: .private), \(errors, privacy: .public) manifest error(s))")
        return context
    }

    /// Unloads extension `identifier` (its decisions are remembered).
    func unload(identifier: String) {
        guard let context = contexts.removeValue(forKey: identifier) else {
            return
        }
        saveState(of: context, identifier: identifier)
        do {
            try controller.unload(context)
            Logger.extensions.info("Extension unloaded (\(identifier, privacy: .private))")
        } catch {
            Logger.extensions.error("Extension not unloaded: \(error.logSummary, privacy: .public)")
        }
    }

    /// Forgets the uninstalled extension `identifier` (`+Installed`).
    func forget(_ identifier: String) {
        installed[identifier] = nil
    }

    /// An action changed (task 6.5: extension buttons).
    func actionDidUpdate() {
        actionRevision &+= 1
    }

    /// The buttons to show have changed (task 6.5).
    func buttonsDidChange() {
        buttonsRevision &+= 1
    }
}
