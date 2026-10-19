import AppKit
import OSLog
import WebKit

/// Delegate of the extension controller (task 6.3): windows, new tabs and windows, options page, permission requests
/// and an action's popover. Matcha has only one main browser window (`DECISIONS.md`):
/// - a new tab goes to the top of the Today tabs of the displayed Space (after its parent tab if it belongs to this
///   Space), in the requested window, otherwise the active window, otherwise the main window; never in a private window
///   for an extension that has no access to it; the requested index is ignored;
/// - a new “popup” window is a mini window (its first address); a “normal” window gives tabs in the browser window; a
///   private window is refused; the tabs to move are ignored;
/// - an extension page (options, `webkit-extension:`) opens in a tab created with its extension's configuration, as
///   WebKit requires.
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
        guard configuration.url.map({ ExtensionURLPolicy.allows($0, from: context.baseURL) }) ?? true else {
            completionHandler(nil, ExtensionError.forbiddenURL)
            return
        }
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
        guard configuration.tabURLs.allSatisfy({ ExtensionURLPolicy.allows($0, from: context.baseURL) }) else {
            completionHandler(nil, ExtensionError.forbiddenURL)
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
        // At the top of the Today tabs, in the requested order (opened from last to first); the first one is active.
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

    /// All or nothing: the whole request is granted if the user accepts; otherwise nothing, and the refusal is
    /// remembered for a day (`ExtensionPromptPolicy`, audit E5): the extension can't ask again and again.
    func webExtensionController(
        _: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in _: (any WKWebExtensionTab)?,
        for context: WKWebExtensionContext,
        completionHandler: @escaping @Sendable (Set<WKWebExtension.Permission>, Date?) -> Void,
    ) {
        let request = ExtensionPermissionRequest(extensionName: displayName(of: context), permissions: permissions.map(\.rawValue))
        ask(request, for: context) { allowed in
            if !allowed {
                let expiration = ExtensionPromptPolicy.denialExpiration(from: .now)
                permissions.forEach { context.setPermissionStatus(.deniedExplicitly, for: $0, expirationDate: expiration) }
            }
            completionHandler(allowed ? permissions : [], nil)
        }
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
        ask(request, for: context) { allowed in
            if !allowed {
                let expiration = ExtensionPromptPolicy.denialExpiration(from: .now)
                matchPatterns.forEach { context.setPermissionStatus(.deniedExplicitly, for: $0, expirationDate: expiration) }
            }
            completionHandler(allowed ? matchPatterns : [], nil)
        }
    }

    func webExtensionController(
        _: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in _: (any WKWebExtensionTab)?,
        for context: WKWebExtensionContext,
        completionHandler: @escaping @Sendable (Set<URL>, Date?) -> Void,
    ) {
        let request = ExtensionPermissionRequest(extensionName: displayName(of: context), urls: urls)
        ask(request, for: context) { allowed in
            if !allowed {
                let expiration = ExtensionPromptPolicy.denialExpiration(from: .now)
                urls.forEach { context.setPermissionStatus(.deniedExplicitly, for: $0, expirationDate: expiration) }
            }
            completionHandler(allowed ? urls : [], nil)
        }
    }

    // MARK: Native Messages

    /// Messages to an app (`runtime.sendNativeMessage`): refused, as WebKit would do (the channel to a Safari
    /// extension's app is reserved for Safari), but by Matcha, without trying to open the app, and with spaced-out
    /// answers (`NativeMessageThrottle`): an extension that sends them in a loop no longer keeps the processor busy.
    func webExtensionController(
        _: WKWebExtensionController,
        sendMessage _: Any,
        toApplicationWithIdentifier _: String?,
        for context: WKWebExtensionContext,
        replyHandler: @escaping @Sendable (Any?, (any Error)?) -> Void,
    ) {
        let identifier = context.uniqueIdentifier
        if nativeMessageSenders.insert(identifier).inserted {
            Logger.extensions.notice("Messages natifs refusés (\(identifier, privacy: .private))")
        }
        let delay = nativeMessages.delay(for: identifier, at: .now)
        Task {
            try? await Task.sleep(for: delay)
            replyHandler(nil, ExtensionError.nativeMessagingUnsupported)
        }
    }

    /// Long-lived connection to an app (`runtime.connectNative`): refused.
    func webExtensionController(
        _: WKWebExtensionController,
        connectUsing _: WKWebExtension.MessagePort,
        for _: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any Error)?) -> Void,
    ) {
        completionHandler(ExtensionError.nativeMessagingUnsupported)
    }

    // MARK: Actions

    /// The action's popover, in the window of its tab, otherwise the active window.
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
