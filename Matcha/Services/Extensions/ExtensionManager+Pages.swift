import AppKit
import OSLog
import WebKit

/// Tabs and mini windows opened for extensions, and requests to the user (task 6.3).
extension ExtensionManager {
    /// Configuration of an extension page (`webkit-extension:`) opened in a tab or a mini window: that of its extension
    /// (otherwise WebKit refuses the navigation), with a per-page content controller (task 6.2); nil for another
    /// address or an extension that is not loaded.
    func pageConfiguration(for url: URL) -> WKWebViewConfiguration? {
        guard Self.isExtensionURL(url), let configuration = context(for: url)?.webViewConfiguration else {
            return nil
        }
        configuration.userContentController = WebConfigurationFactory.makeUserContentController()
        return configuration
    }

    /// Browser window in which to open tabs: `requested` if it is one, otherwise the active window, otherwise the main
    /// window; a private window only for an extension that has access to it.
    func browserWindow(for requested: (any WKWebExtensionWindow)?, context: WKWebExtensionContext) -> WindowModel? {
        let allowsPrivate = context.hasAccessToPrivateData
        for candidate in [requested as? ExtensionWindow, windows.focusedWindow] {
            if case let .browser(model, _)? = candidate?.owner, allowsPrivate || !model.session.isPrivate {
                return model
            }
        }
        let models = windows.browserWindows.compactMap(\.model)
        return models.first { !$0.session.isPrivate } ?? (allowsPrivate ? models.first : nil)
    }

    /// Opens `url` (none: an empty tab) in the Space displayed by `model`, at the top of the Today tabs, or after
    /// `parent` if it belongs to this Space; active (selected) and pinned on request.
    @discardableResult
    func openTab(_ url: URL?, in model: WindowModel, after parent: BrowserTab?, isActive: Bool, isPinned: Bool) -> BrowserTab {
        let tabManager = model.space.tabManager
        let configuration = url.flatMap(pageConfiguration(for:))
            ?? tabManager.pages.makeConfiguration(websiteDataStore: tabManager.websiteDataStore)
        let anchor = parent.flatMap { tabManager.tab(withID: $0.id) === $0 ? $0 : nil }
        let tab = tabManager.insertTab(configuration: configuration, after: anchor, select: isActive)
        if let url {
            tab.load(url)
        }
        if isPinned {
            tabManager.setPlace(tab, to: .pinned)
        }
        windows.update()
        Logger.extensions.info("Tab opened for an extension")
        return tab
    }

    /// Mini window (an extension's “popup” window) on `url`, in the profile of the displayed Space; without an address,
    /// its input bar opens.
    @discardableResult
    func openMiniWindow(_ url: URL?, in miniWindows: MiniWindowManager) -> MiniWindowController {
        let profile = miniWindows.displayedSpace.record.profile
        let configuration = url.flatMap(pageConfiguration(for:))
            ?? miniWindows.makeConfiguration(miniWindows.session.dataStore(for: profile))
        let controller = miniWindows.show(BrowserTab(configuration: configuration), profileID: profile?.id)
        if let url {
            controller.tab.load(url)
            controller.showWebView()
        } else {
            controller.showCommandBar(.newSearch)
        }
        windows.update()
        Logger.extensions.info("Mini window opened for an extension")
        return controller
    }

    /// Name of the extension for the user.
    func displayName(of context: WKWebExtensionContext) -> String {
        context.webExtension.displayName ?? context.uniqueIdentifier
    }

    /// Asks the user (`permissionPrompter`); an empty request is denied without showing anything.
    func ask(_ request: ExtensionPermissionRequest, for context: WKWebExtensionContext, completion: @escaping @MainActor (Bool) -> Void) {
        let key = ObjectIdentifier(context)
        guard !request.isEmpty, !promptingContexts.contains(key) else {
            completion(false)
            return
        }
        promptingContexts.insert(key)
        permissionPrompter.ask(request) { [weak self] allowed in
            self?.promptingContexts.remove(key)
            Logger.extensions.info("Permission request \(allowed ? "granted" : "denied", privacy: .public)")
            completion(allowed)
        }
    }

    /// The user removes an extension's access to a website (Settings): it may ask again.
    func revokeSite(_ pattern: String, identifier: String) {
        if let context = contexts[identifier], let matchPattern = try? WKWebExtension.MatchPattern(string: pattern) {
            context.setPermissionStatus(.unknown, for: matchPattern)
            saveState(of: context, identifier: identifier)
        } else if var state = store.state(for: identifier) {
            state.grantedMatchPatterns[pattern] = nil
            store.setState(state, for: identifier)
        }
    }
}
