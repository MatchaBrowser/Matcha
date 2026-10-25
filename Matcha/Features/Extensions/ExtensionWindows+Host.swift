import AppKit
import OSLog
import WebKit

/// The windows as the extension manager's host (`ExtensionHost`, audit C1). Matcha has several browser windows on the
/// same Spaces (`DECISIONS.md`):
/// - a new tab goes to the top of the Today tabs of the displayed Space (after its parent tab if it belongs to this
///   Space), in the requested window, otherwise the active window, otherwise the main window; never in a private window
///   for an extension that has no access to it; the requested index is ignored;
/// - a new “popup” window is a mini window (its first address); a “normal” window gives tabs in the browser window; the
///   tabs to move are ignored;
/// - an extension page (options, `webkit-extension:`) opens in a tab created with its extension's configuration, as
///   WebKit requires.
extension ExtensionWindows: ExtensionHost {
    var windowsForExtensions: [any WKWebExtensionWindow] {
        orderedWindows
    }

    var focusedWindowForExtensions: (any WKWebExtensionWindow)? {
        focusedWindow
    }

    func extensionTab(for page: BrowserTab) -> (any WKWebExtensionTab)? {
        adapter(for: page)
    }

    func openTab(using configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext) throws -> any WKWebExtensionTab {
        guard let model = browserWindow(for: configuration.window, context: context) else {
            throw ExtensionError.noBrowserWindow
        }
        let tab = openTab(
            configuration.url,
            in: model,
            after: (configuration.parentTab as? ExtensionTab)?.page,
            isActive: configuration.shouldBeActive,
            isPinned: configuration.shouldBePinned,
        )
        guard let adapter = adapter(for: tab) else {
            throw ExtensionError.noBrowserWindow
        }
        return adapter
    }

    func openWindow(
        using configuration: WKWebExtension.WindowConfiguration,
        for context: WKWebExtensionContext,
    ) throws -> any WKWebExtensionWindow {
        if configuration.windowType == .popup, let miniWindows {
            let controller = openMiniWindow(configuration.tabURLs.first, in: miniWindows)
            return windowAdapter(controller.id)
        }
        guard let model = browserWindow(for: nil, context: context) else {
            throw ExtensionError.noBrowserWindow
        }
        // At the top of the Today tabs, in the requested order (opened from last to first); the first one is active. The
        // extensions' view of the windows is updated once, at the end (review EX18).
        let urls: [URL?] = configuration.tabURLs.isEmpty ? [nil] : configuration.tabURLs
        let first = urls.reversed().map { openTab($0, in: model, after: nil, isActive: false, isPinned: false, updates: false) }.last
        if let first {
            model.activate()
            model.tabManager.select(first)
            update()
        }
        if configuration.shouldBeFocused {
            adapter(for: model)?.owner?.nsWindow?.makeKeyAndOrderFront(nil)
        }
        guard let adapter = adapter(for: model) else {
            throw ExtensionError.noBrowserWindow
        }
        return adapter
    }

    func openPage(_ url: URL, for context: WKWebExtensionContext?) -> Bool {
        // An extension's page (options) opens only at an address it may open (review EX12).
        if let context, !ExtensionURLPolicy.allows(url, from: context.baseURL) {
            Logger.extensions.notice("Extension page refused: address not allowed")
            return false
        }
        let model = context.map { browserWindow(for: nil, context: $0) }
            ?? browserWindows.compactMap(\.model).first { !$0.session.isPrivate }
        guard let model else {
            return false
        }
        openTab(url, in: model, after: nil, isActive: true, isPinned: false)
        adapter(for: model)?.owner?.nsWindow?.makeKeyAndOrderFront(nil)
        return true
    }

    /// In the window of the action's tab, otherwise the active window.
    func presentPopup(of action: WKWebExtension.Action) -> Bool {
        let tabWindow = (action.associatedTab as? ExtensionTab)?.windowID.flatMap { owner(ofWindow: $0)?.nsWindow }
        let window = tabWindow ?? focusedWindow?.owner?.nsWindow ?? NSApp.keyWindow
        return popups.present(action, in: window)
    }

    // MARK: Opening

    /// Browser window in which to open tabs: `requested` if it is one, otherwise the active window, otherwise the main
    /// window; a private window only for an extension that has access to it.
    func browserWindow(for requested: (any WKWebExtensionWindow)?, context: WKWebExtensionContext) -> WindowModel? {
        let allowsPrivate = context.hasAccessToPrivateData
        for candidate in [requested as? ExtensionWindow, focusedWindow] {
            if case let .browser(model, _)? = candidate?.owner, allowsPrivate || !model.session.isPrivate {
                return model
            }
        }
        let models = browserWindows.compactMap(\.model)
        return models.first { !$0.session.isPrivate } ?? (allowsPrivate ? models.first : nil)
    }

    /// Opens `url` (none: an empty tab) in the Space displayed by `model`, at the top of the Today tabs, or after
    /// `parent` if it belongs to this Space; active (selected) and pinned on request.
    @discardableResult
    func openTab(
        _ url: URL?,
        in model: WindowModel,
        after parent: BrowserTab?,
        isActive: Bool,
        isPinned: Bool,
        updates: Bool = true,
    ) -> BrowserTab {
        let tabManager = model.tabManager
        // Selected in that window, even if another one shows the same Space.
        model.activate()
        let configuration = url.flatMap { manager?.pageConfiguration(for: $0) }
            ?? tabManager.pages.makeConfiguration(websiteDataStore: tabManager.websiteDataStore)
        let anchor = parent.flatMap { tabManager.tab(withID: $0.id) === $0 ? $0 : nil }
        let tab = tabManager.insertTab(configuration: configuration, after: anchor, select: isActive)
        if let url {
            tab.load(url)
        }
        if isPinned {
            tabManager.setPlace(tab, to: .pinned)
        }
        if updates {
            update()
        }
        Logger.extensions.info("Tab opened for an extension")
        return tab
    }

    /// Mini window (an extension's “popup” window) on `url`, in the profile of the displayed Space; without an address,
    /// its input bar opens.
    @discardableResult
    func openMiniWindow(_ url: URL?, in miniWindows: MiniWindowManager) -> MiniWindowController {
        let profile = miniWindows.displayedSpace.record.profile
        let configuration = url.flatMap { manager?.pageConfiguration(for: $0) }
            ?? miniWindows.makeConfiguration(miniWindows.session.dataStore(for: profile))
        let controller = miniWindows.show(BrowserTab(configuration: configuration), profileID: profile?.id)
        if let url {
            controller.tab.load(url)
            controller.showWebView()
        } else {
            controller.showCommandBar(.newSearch)
        }
        update()
        Logger.extensions.info("Mini window opened for an extension")
        return controller
    }
}
