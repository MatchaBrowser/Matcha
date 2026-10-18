import AppKit
import OSLog
import WebKit

/// Onglets et mini-fenêtres ouverts pour les extensions, et demandes à l'utilisateur (tâche 6.3).
extension ExtensionManager {
    /// Configuration d'une page d'extension (`webkit-extension:`) ouverte dans un onglet ou une mini-fenêtre : celle de
    /// son extension (WebKit refuse sinon la navigation), avec un contrôleur de contenu à la page (tâche 6.2) ; nil pour
    /// une autre adresse ou une extension non chargée.
    func pageConfiguration(for url: URL) -> WKWebViewConfiguration? {
        guard Self.isExtensionURL(url), let configuration = context(for: url)?.webViewConfiguration else {
            return nil
        }
        configuration.userContentController = WebConfigurationFactory.makeUserContentController()
        return configuration
    }

    /// Fenêtre de navigation où ouvrir des onglets : `requested` si c'en est une, sinon la fenêtre active, sinon la
    /// fenêtre principale ; une fenêtre privée seulement pour une extension qui y a accès.
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

    /// Ouvre `url` (rien : un onglet vide) dans le Space affiché par `model`, en tête des onglets du jour, ou après
    /// `parent` s'il est de ce Space ; actif (sélectionné) et épinglé à la demande.
    @discardableResult
    func openTab(_ url: URL?, in model: WindowModel, after parent: BrowserTab?, isActive: Bool, isPinned: Bool) -> BrowserTab {
        let tabManager = model.space.tabManager
        let configuration = url.flatMap(pageConfiguration(for:))
            ?? WebConfigurationFactory.makeConfiguration(websiteDataStore: tabManager.websiteDataStore)
        let anchor = parent.flatMap { tabManager.tab(withID: $0.id) === $0 ? $0 : nil }
        let tab = tabManager.insertTab(configuration: configuration, after: anchor, select: isActive)
        if let url {
            tab.load(url)
        }
        if isPinned {
            tabManager.setPlace(tab, to: .pinned)
        }
        windows.update()
        Logger.extensions.info("Onglet ouvert pour une extension")
        return tab
    }

    /// Mini-fenêtre (fenêtre « popup » d'une extension) sur `url`, dans le profil du Space affiché ; sans adresse, sa
    /// barre de saisie s'ouvre.
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
        Logger.extensions.info("Mini-fenêtre ouverte pour une extension")
        return controller
    }

    /// Nom de l'extension pour l'utilisateur.
    func displayName(of context: WKWebExtensionContext) -> String {
        context.webExtension.displayName ?? context.uniqueIdentifier
    }

    /// Pose la question à l'utilisateur (`permissionPrompter`) ; une demande vide est refusée sans rien montrer.
    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (Bool) -> Void) {
        guard !request.isEmpty else {
            completion(false)
            return
        }
        permissionPrompter.ask(request) { allowed in
            Logger.extensions.info("Demande de permissions \(allowed ? "accordée" : "refusée", privacy: .public)")
            completion(allowed)
        }
    }
}
