import Foundation
import Observation
import WebKit

/// Extension buttons next to the address (task 6.5, audit C3): which ones to show, hiding or showing them, and the
/// action of a click (popover or the extension's `action.onClicked`).
@MainActor
@Observable
final class ExtensionToolbar {
    /// Changes at each update of an action (icon, title, badge): the buttons follow it. WebKit's actions aren't
    /// observable.
    private(set) var actionRevision = 0
    /// Changes when the buttons to show change (button hidden or shown, private windows).
    private(set) var buttonsRevision = 0
    @ObservationIgnored private unowned let manager: ExtensionManager

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    /// Extensions whose button is displayed, by name: loaded, button not hidden; in a private window, only those that
    /// have access to it.
    func buttonExtensions(isPrivate: Bool) -> [(identifier: String, context: WKWebExtensionContext)] {
        _ = buttonsRevision
        return manager.contexts
            .filter { showsButton($0.key) && (!isPrivate || $0.value.hasAccessToPrivateData) }
            .map { (identifier: $0.key, context: $0.value) }
            .sorted { Self.name(of: $0.context).localizedStandardCompare(Self.name(of: $1.context)) == .orderedAscending }
    }

    /// True if the button of extension `identifier` is displayed next to the address (yes by default).
    func showsButton(_ identifier: String) -> Bool {
        manager.store.state(for: identifier)?.showsButton ?? true
    }

    /// Shows or hides the button of extension `identifier`; remembered. When hidden, the extension keeps acting on
    /// pages.
    func setShowsButton(_ shows: Bool, identifier: String) {
        var state = manager.store.state(for: identifier) ?? ExtensionState()
        state.showsButton = shows ? nil : false
        manager.store.setState(state, for: identifier)
        buttonsDidChange()
    }

    /// Action of extension `identifier` for tab `tab` (icon, title, badge, popup), if it is loaded.
    func action(of identifier: String, for tab: BrowserTab?) -> WKWebExtension.Action? {
        _ = actionRevision
        return manager.contexts[identifier]?.action(for: tab.flatMap { manager.host?.extensionTab(for: $0) })
    }

    /// Click on the button of extension `identifier` for tab `tab`: its popover opens below the button, or the
    /// extension receives the click (`action.onClicked`); it then has access to the page (`activeTab`).
    func performAction(of identifier: String, for tab: BrowserTab?) {
        guard let context = manager.contexts[identifier] else {
            return
        }
        // WebKit reads the targeted tab again: the state must be up to date.
        manager.host?.update(beforeLoading: false)
        let extensionTab = tab.flatMap { manager.host?.extensionTab(for: $0) }
        context.action(for: extensionTab)?.hasUnreadBadgeText = false
        context.performAction(for: extensionTab)
    }

    /// An action changed.
    func actionDidUpdate() {
        actionRevision &+= 1
    }

    /// The buttons to show have changed.
    func buttonsDidChange() {
        buttonsRevision &+= 1
    }

    /// Displayed name of an extension.
    static func name(of context: WKWebExtensionContext) -> String {
        context.webExtension.displayShortName ?? context.webExtension.displayName ?? context.uniqueIdentifier
    }
}
