import AppKit
import WebKit

/// Décisions de l'utilisateur sur les extensions (tâche 6.3) : permissions, sites, fenêtres privées, retenues par
/// `ExtensionStateStore` et remises à chaque chargement.
extension ExtensionManager {
    /// Ouvre (ou ferme) les fenêtres privées à l'extension `identifier` : choix de l'utilisateur seulement (tâche 6.4) ;
    /// retenu, et appliqué tout de suite si elle est chargée.
    func setAccessToPrivateData(_ isAllowed: Bool, identifier: String) {
        defer { buttonsDidChange() }
        if let context = contexts[identifier] {
            context.hasAccessToPrivateData = isAllowed
            saveState(of: context, identifier: identifier)
        } else {
            var state = store.state(for: identifier) ?? ExtensionState()
            state.hasAccessToPrivateData = isAllowed
            store.setState(state, for: identifier)
        }
    }

    /// Retient les décisions actuelles de `context`, chargé sous l'identifiant `identifier` (permissions, sites,
    /// fenêtres privées).
    func saveState(of context: WKWebExtensionContext, identifier: String) {
        guard contexts[identifier] === context || store.state(for: identifier) != nil else {
            return
        }
        let isEnabled = store.state(for: identifier)?.isEnabled ?? true
        store.setState(state(of: context, identifier: identifier, isEnabled: isEnabled), for: identifier)
    }

    /// Retient les décisions de toutes les extensions chargées.
    func saveAllStates() {
        for (identifier, context) in contexts {
            saveState(of: context, identifier: identifier)
        }
    }

    /// État retenu de `context` : ses décisions actuelles, l'emplacement de son `.appex` s'il vient d'une app et
    /// l'affichage de son bouton.
    func state(of context: WKWebExtensionContext, identifier: String, isEnabled: Bool) -> ExtensionState {
        var state = ExtensionState(context: context, isEnabled: isEnabled)
        let stored = store.state(for: identifier)
        state.appExtensionPath = stored?.appExtensionPath
        state.showsButton = stored?.showsButton
        return state
    }

    /// Identifiant de l'extension `identifier` pour WebKit et les sites (`runtime.id`, messages des sites autorisés par
    /// `externally_connectable`) : pour une extension Safari d'app, celui que Safari lui donne (« identifiant du bundle
    /// (équipe) »), que ses sites connaissent ; sinon `identifier`.
    func webExtensionIdentifier(for identifier: String) -> String {
        store.state(for: identifier)?.appExtensionPath
            .flatMap { SafariExtensionFinder.safariIdentifier(ofAppExtensionAt: URL(filePath: $0)) } ?? identifier
    }

    /// Décisions retenues dès que WebKit les change (réponse à une demande, `permissions.remove()`…), et à la fermeture
    /// de l'app.
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
