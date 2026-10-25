import AppKit
import WebKit

/// User decisions about extensions (task 6.3): permissions, websites, private windows, remembered by
/// `ExtensionStateStore` and restored at each load.
extension ExtensionManager {
    /// Opens (or closes) private windows to extension `identifier`: the user's choice only (task 6.4); remembered, and
    /// applied right away if it is loaded.
    func setAccessToPrivateData(_ isAllowed: Bool, identifier: String) {
        defer { toolbar.buttonsDidChange() }
        if let context = contexts[identifier] {
            context.hasAccessToPrivateData = isAllowed
            saveState(of: context, identifier: identifier)
        } else {
            var state = store.state(for: identifier) ?? ExtensionState()
            state.hasAccessToPrivateData = isAllowed
            store.setState(state, for: identifier)
        }
    }

    /// Remembers the current decisions of `context`, loaded under identifier `identifier` (permissions, websites,
    /// private windows).
    func saveState(of context: WKWebExtensionContext, identifier: String) {
        guard contexts[identifier] === context || store.state(for: identifier) != nil else {
            return
        }
        let isEnabled = store.state(for: identifier)?.isEnabled ?? true
        store.setState(state(of: context, identifier: identifier, isEnabled: isEnabled), for: identifier)
    }

    /// Remembers the decisions of all loaded extensions.
    func saveAllStates() {
        for (identifier, context) in contexts {
            saveState(of: context, identifier: identifier)
        }
    }

    /// Remembered state of `context`: its current decisions, the location of its `.appex` if it comes from an app, and
    /// whether its button is displayed.
    func state(of context: WKWebExtensionContext, identifier: String, isEnabled: Bool) -> ExtensionState {
        var state = ExtensionState(context: context, isEnabled: isEnabled)
        let stored = store.state(for: identifier)
        state.appExtensionPath = stored?.appExtensionPath
        state.showsButton = stored?.showsButton
        state.publisher = stored?.publisher
        state.version = stored?.version
        state.appExtensionIdentity = stored?.appExtensionIdentity
        state.baseURLHost = stored?.baseURLHost
        // A site granted again is no longer removed.
        state.revokedMatchPatterns = (stored?.revokedMatchPatterns ?? []).subtracting(state.grantedMatchPatterns.keys)
        return state
    }

    /// Identifier of extension `identifier` for WebKit and websites (`runtime.id`, messages from websites allowed by
    /// `externally_connectable`): for an app's Safari extension, the one Safari gives it (“bundle identifier (team)”),
    /// which its websites know; otherwise `identifier`. The identity remembered at installation, without checking the
    /// signature again (review EX7), and still known once the app is deleted (its data can then be erased, review EX5).
    func webExtensionIdentifier(for identifier: String) -> String {
        guard let state = store.state(for: identifier), let path = state.appExtensionPath else {
            return identifier
        }
        return state.appExtensionIdentity ?? SafariExtensionFinder.safariIdentifier(ofAppExtensionAt: URL(filePath: path)) ?? identifier
    }

    /// Decisions remembered as soon as WebKit changes them (answer to a request, `permissions.remove()`…), and when the
    /// app quits.
    func observeContexts() {
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
        // All loaded extensions are read again (nothing is written for those that have not changed): the notification
        // does not cross the isolation boundary.
        for name in names + [NSApplication.willTerminateNotification] {
            observers.append(NotificationObservation(of: name) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveAllStates()
                }
            })
        }
    }
}
