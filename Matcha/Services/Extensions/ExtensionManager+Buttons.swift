import Foundation
import WebKit

/// Extension buttons next to the address (task 6.5): which ones to show, hiding or showing them, and the action of a
/// click (popover or the extension's `action.onClicked`).
extension ExtensionManager {
    /// Matcha's identifier for `context` (settings, folder), if it is loaded.
    func identifier(of context: WKWebExtensionContext) -> String? {
        contexts.first { $0.value === context }?.key
    }

    /// Extensions whose button is displayed, by name: loaded, button not hidden; in a private window, only those that
    /// have access to it.
    func buttonExtensions(isPrivate: Bool) -> [(identifier: String, context: WKWebExtensionContext)] {
        _ = buttonsRevision
        return contexts
            .filter { showsButton($0.key) && (!isPrivate || $0.value.hasAccessToPrivateData) }
            .map { (identifier: $0.key, context: $0.value) }
            .sorted { Self.name(of: $0.context).localizedStandardCompare(Self.name(of: $1.context)) == .orderedAscending }
    }

    /// True if the button of extension `identifier` is displayed next to the address (yes by default).
    func showsButton(_ identifier: String) -> Bool {
        store.state(for: identifier)?.showsButton ?? true
    }

    /// Shows or hides the button of extension `identifier`; remembered. When hidden, the extension keeps acting on
    /// pages.
    func setShowsButton(_ shows: Bool, identifier: String) {
        var state = store.state(for: identifier) ?? ExtensionState()
        state.showsButton = shows ? nil : false
        store.setState(state, for: identifier)
        buttonsDidChange()
    }

    /// Action of extension `identifier` for tab `tab` (icon, title, badge, popup), if it is loaded.
    func action(of identifier: String, for tab: BrowserTab?) -> WKWebExtension.Action? {
        _ = actionRevision
        return contexts[identifier]?.action(for: tab.flatMap(windows.adapter(for:)))
    }

    /// Click on the button of extension `identifier` for tab `tab`: its popover opens below the button, or the
    /// extension receives the click (`action.onClicked`); it then has access to the page (`activeTab`).
    func performAction(of identifier: String, for tab: BrowserTab?) {
        guard let context = contexts[identifier] else {
            return
        }
        // WebKit reads the targeted tab again: the state must be up to date.
        windows.update()
        let extensionTab = tab.flatMap(windows.adapter(for:))
        context.action(for: extensionTab)?.hasUnreadBadgeText = false
        context.performAction(for: extensionTab)
    }

    /// Displayed name of an extension.
    static func name(of context: WKWebExtensionContext) -> String {
        context.webExtension.displayShortName ?? context.webExtension.displayName ?? context.uniqueIdentifier
    }
}
