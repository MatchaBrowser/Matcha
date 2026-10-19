import Foundation
import OSLog
import WebKit

/// Delegate of the extension controller (task 6.3, audit C3): windows and new pages go to the manager's host
/// (`ExtensionHost`, the interface), permission requests to its prompter; options page, native messages, an action's
/// popover. Rules:
/// - only web pages, `about:blank` and the extension's own pages can be opened (`ExtensionURLPolicy`, audit E4);
/// - a private window is never opened for an extension;
/// - without a host (no interface), nothing opens.
@MainActor
final class ExtensionControllerDelegate: NSObject, WKWebExtensionControllerDelegate {
    private unowned let manager: ExtensionManager

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func webExtensionController(_: WKWebExtensionController, openWindowsFor _: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        manager.host?.windowsForExtensions ?? []
    }

    func webExtensionController(_: WKWebExtensionController, focusedWindowFor _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        manager.host?.focusedWindowForExtensions
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
        guard let host = manager.host else {
            completionHandler(nil, ExtensionError.noBrowserWindow)
            return
        }
        do {
            try completionHandler(host.openTab(using: configuration, for: context), nil)
        } catch {
            completionHandler(nil, error)
        }
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
        guard let host = manager.host else {
            completionHandler(nil, ExtensionError.noBrowserWindow)
            return
        }
        do {
            try completionHandler(host.openWindow(using: configuration, for: context), nil)
        } catch {
            completionHandler(nil, error)
        }
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
        completionHandler(manager.host?.openPage(url, for: context) == true ? nil : ExtensionError.noBrowserWindow)
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
        let request = ExtensionPermissionRequest(extensionName: manager.displayName(of: context), permissions: permissions.map(\.rawValue))
        manager.ask(request, for: context) { allowed in
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
            extensionName: manager.displayName(of: context),
            matchPatterns: matchPatterns.map(\.string),
            includesAllWebsites: matchPatterns.contains(where: \.matchesAllHosts),
        )
        manager.ask(request, for: context) { allowed in
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
        let request = ExtensionPermissionRequest(extensionName: manager.displayName(of: context), urls: urls)
        manager.ask(request, for: context) { allowed in
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
        if manager.nativeMessageSenders.insert(identifier).inserted {
            Logger.extensions.notice("Native messages refused (\(identifier, privacy: .private))")
        }
        let delay = manager.nativeMessages.delay(for: identifier, at: .now)
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

    /// The action's popover, below its button (`ExtensionHost.presentPopup`).
    func webExtensionController(
        _: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for _: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any Error)?) -> Void,
    ) {
        guard manager.host?.presentPopup(of: action) == true else {
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
        manager.toolbar.actionDidUpdate()
    }
}
