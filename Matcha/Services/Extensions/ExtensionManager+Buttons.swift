import Foundation
import WebKit

/// Boutons des extensions près de l'adresse (tâche 6.5) : lesquels montrer, les masquer ou les afficher, et l'action
/// d'un clic (bulle ou `action.onClicked` de l'extension).
extension ExtensionManager {
    /// Identifiant de Matcha de `context` (réglages, dossier), s'il est chargé.
    func identifier(of context: WKWebExtensionContext) -> String? {
        contexts.first { $0.value === context }?.key
    }

    /// Extensions dont le bouton s'affiche, par nom : chargées, bouton non masqué ; dans une fenêtre privée, seulement
    /// celles qui y ont accès.
    func buttonExtensions(isPrivate: Bool) -> [(identifier: String, context: WKWebExtensionContext)] {
        _ = buttonsRevision
        return contexts
            .filter { showsButton($0.key) && (!isPrivate || $0.value.hasAccessToPrivateData) }
            .map { (identifier: $0.key, context: $0.value) }
            .sorted { Self.name(of: $0.context).localizedStandardCompare(Self.name(of: $1.context)) == .orderedAscending }
    }

    /// Vrai si le bouton de l'extension `identifier` s'affiche près de l'adresse (oui par défaut).
    func showsButton(_ identifier: String) -> Bool {
        store.state(for: identifier)?.showsButton ?? true
    }

    /// Affiche ou masque le bouton de l'extension `identifier` ; retenu. Masqué, l'extension continue d'agir sur les
    /// pages.
    func setShowsButton(_ shows: Bool, identifier: String) {
        var state = store.state(for: identifier) ?? ExtensionState()
        state.showsButton = shows ? nil : false
        store.setState(state, for: identifier)
        buttonsDidChange()
    }

    /// Action de l'extension `identifier` pour l'onglet `tab` (icône, titre, badge, popup), si elle est chargée.
    func action(of identifier: String, for tab: BrowserTab?) -> WKWebExtension.Action? {
        _ = actionRevision
        return contexts[identifier]?.action(for: tab.flatMap(windows.adapter(for:)))
    }

    /// Clic sur le bouton de l'extension `identifier` pour l'onglet `tab` : sa bulle s'ouvre sous le bouton, ou
    /// l'extension reçoit le clic (`action.onClicked`) ; elle a alors accès à la page (`activeTab`).
    func performAction(of identifier: String, for tab: BrowserTab?) {
        guard let context = contexts[identifier] else {
            return
        }
        // WebKit relit l'onglet visé : l'état doit être à jour.
        windows.update()
        let extensionTab = tab.flatMap(windows.adapter(for:))
        context.action(for: extensionTab)?.hasUnreadBadgeText = false
        context.performAction(for: extensionTab)
    }

    /// Nom affiché d'une extension.
    static func name(of context: WKWebExtensionContext) -> String {
        context.webExtension.displayShortName ?? context.webExtension.displayName ?? context.uniqueIdentifier
    }
}
