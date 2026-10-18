import AppKit
import OSLog
import WebKit

/// Délégué du contrôleur des extensions (tâche 6.3) : fenêtres, nouveaux onglets et fenêtres, page d'options, demandes
/// de permissions et bulle d'une action. Matcha n'a qu'une fenêtre de navigation principale (`DECISIONS.md`) :
/// - un nouvel onglet va en tête des onglets du jour du Space affiché (après son onglet parent s'il est de ce Space),
///   dans la fenêtre demandée, sinon la fenêtre active, sinon la fenêtre principale ; jamais dans une fenêtre privée
///   pour une extension qui n'y a pas accès ; le rang demandé est ignoré ;
/// - une nouvelle fenêtre « popup » est une mini-fenêtre (sa première adresse) ; une fenêtre « normal » donne des onglets
///   dans la fenêtre de navigation ; une fenêtre privée est refusée ; les onglets à déplacer sont ignorés ;
/// - une page d'extension (options, `webkit-extension:`) s'ouvre dans un onglet créé avec la configuration de son
///   extension, comme l'exige WebKit.
extension ExtensionManager: WKWebExtensionControllerDelegate {
    func webExtensionController(_: WKWebExtensionController, openWindowsFor _: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        windows.orderedWindows
    }

    func webExtensionController(_: WKWebExtensionController, focusedWindowFor _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        windows.focusedWindow
    }

    func webExtensionController(
        _: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for context: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any WKWebExtensionTab)?, (any Error)?) -> Void,
    ) {
        guard let model = browserWindow(for: configuration.window, context: context) else {
            completionHandler(nil, ExtensionError.noBrowserWindow)
            return
        }
        let tab = openTab(
            configuration.url,
            in: model,
            after: (configuration.parentTab as? ExtensionTab)?.page,
            isActive: configuration.shouldBeActive,
            isPinned: configuration.shouldBePinned,
        )
        completionHandler(windows.adapter(for: tab), nil)
    }

    func webExtensionController(
        _: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for context: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any WKWebExtensionWindow)?, (any Error)?) -> Void,
    ) {
        guard !configuration.shouldBePrivate else {
            completionHandler(nil, ExtensionError.unsupported("Private windows cannot be opened by extensions."))
            return
        }
        if configuration.windowType == .popup, let miniWindows = windows.miniWindows {
            let controller = openMiniWindow(configuration.tabURLs.first, in: miniWindows)
            completionHandler(windows.windowAdapter(controller.id), nil)
            return
        }
        guard let model = browserWindow(for: nil, context: context) else {
            completionHandler(nil, ExtensionError.noBrowserWindow)
            return
        }
        // En tête des onglets du jour, dans l'ordre demandé (ouverts du dernier au premier) ; le premier est actif.
        let urls: [URL?] = configuration.tabURLs.isEmpty ? [nil] : configuration.tabURLs
        let first = urls.reversed().map { openTab($0, in: model, after: nil, isActive: false, isPinned: false) }.last
        if let first {
            model.space.tabManager.select(first)
            windows.update()
        }
        if configuration.shouldBeFocused {
            windows.adapter(for: model)?.owner?.nsWindow?.makeKeyAndOrderFront(nil)
        }
        completionHandler(windows.adapter(for: model), nil)
    }

    func webExtensionController(
        _: WKWebExtensionController,
        openOptionsPageFor context: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any Error)?) -> Void,
    ) {
        guard let url = context.optionsPageURL else {
            completionHandler(ExtensionError.unsupported("The extension has no options page."))
            return
        }
        guard let model = browserWindow(for: nil, context: context) else {
            completionHandler(ExtensionError.noBrowserWindow)
            return
        }
        openTab(url, in: model, after: nil, isActive: true, isPinned: false)
        completionHandler(nil)
    }

    // MARK: Permissions

    /// Tout ou rien : la demande entière est accordée si l'utilisateur accepte, sinon rien (rien n'est retenu comme
    /// refusé : l'extension pourra redemander).
    func webExtensionController(
        _: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in _: (any WKWebExtensionTab)?,
        for context: WKWebExtensionContext,
        completionHandler: @escaping @Sendable (Set<WKWebExtension.Permission>, Date?) -> Void,
    ) {
        let request = ExtensionPermissionRequest(extensionName: displayName(of: context), permissions: permissions.map(\.rawValue))
        ask(request) { completionHandler($0 ? permissions : [], nil) }
    }

    func webExtensionController(
        _: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in _: (any WKWebExtensionTab)?,
        for context: WKWebExtensionContext,
        completionHandler: @escaping @Sendable (Set<WKWebExtension.MatchPattern>, Date?) -> Void,
    ) {
        let request = ExtensionPermissionRequest(
            extensionName: displayName(of: context),
            matchPatterns: matchPatterns.map(\.string),
            includesAllWebsites: matchPatterns.contains(where: \.matchesAllHosts),
        )
        ask(request) { completionHandler($0 ? matchPatterns : [], nil) }
    }

    func webExtensionController(
        _: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in _: (any WKWebExtensionTab)?,
        for context: WKWebExtensionContext,
        completionHandler: @escaping @Sendable (Set<URL>, Date?) -> Void,
    ) {
        let request = ExtensionPermissionRequest(extensionName: displayName(of: context), urls: urls)
        ask(request) { completionHandler($0 ? urls : [], nil) }
    }

    // MARK: Messages natifs

    /// Messages vers une app (`runtime.sendNativeMessage`) : refusés, comme WebKit le ferait (le passage vers l'app d'une
    /// extension Safari est réservé à Safari), mais par Matcha, sans essai d'ouvrir l'app, et avec des réponses
    /// espacées (`NativeMessageThrottle`) : une extension qui en envoie en boucle n'occupe plus le processeur.
    func webExtensionController(
        _: WKWebExtensionController,
        sendMessage _: Any,
        toApplicationWithIdentifier _: String?,
        for context: WKWebExtensionContext,
        replyHandler: @escaping @Sendable (Any?, (any Error)?) -> Void,
    ) {
        let identifier = context.uniqueIdentifier
        if nativeMessageSenders.insert(identifier).inserted {
            Logger.extensions.notice("Messages natifs refusés (\(identifier, privacy: .public))")
        }
        let delay = nativeMessages.delay(for: identifier, at: .now)
        Task {
            try? await Task.sleep(for: delay)
            replyHandler(nil, ExtensionError.nativeMessagingUnsupported)
        }
    }

    /// Connexion durable vers une app (`runtime.connectNative`) : refusée.
    func webExtensionController(
        _: WKWebExtensionController,
        connectUsing _: WKWebExtension.MessagePort,
        for _: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any Error)?) -> Void,
    ) {
        completionHandler(ExtensionError.nativeMessagingUnsupported)
    }

    // MARK: Actions

    /// Bulle de l'action, dans la fenêtre de son onglet, sinon la fenêtre active.
    func webExtensionController(
        _: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for _: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any Error)?) -> Void,
    ) {
        let tabWindow = (action.associatedTab as? ExtensionTab)?.windowID.flatMap { windows.owner(ofWindow: $0)?.nsWindow }
        let window = tabWindow ?? windows.focusedWindow?.owner?.nsWindow ?? NSApp.keyWindow
        guard popups.present(action, in: window) else {
            completionHandler(ExtensionError.unsupported("The popup cannot be shown."))
            return
        }
        completionHandler(nil)
    }

    func webExtensionController(
        _: WKWebExtensionController,
        didUpdate _: WKWebExtension.Action,
        forExtensionContext _: WKWebExtensionContext,
    ) {
        actionDidUpdate()
    }
}
