import Foundation
import OSLog
import WebKit

/// Extensions installées (tâches 6.3 et 6.4) : celles du dossier des extensions et les extensions Safari d'apps, lues
/// au lancement, chargées si elles sont actives ; activer, désactiver, désinstaller, page d'options.
extension ExtensionManager {
    /// Identifiants des extensions installées : dossiers de `directory`, puis extensions Safari d'apps retenues.
    var installedIdentifiers: [String] {
        let folders = directory.map { ExtensionInstallDirectory.installedExtensions(in: $0).map(\.identifier) } ?? []
        return folders + store.appExtensions.map(\.identifier).filter { !folders.contains($0) }
    }

    /// Lit en tâche de fond les extensions installées et charge celles qui sont actives. Sans effet au second appel.
    func start() {
        guard !isStarted, directory != nil else {
            return
        }
        isStarted = true
        let identifiers = installedIdentifiers
        Task {
            for identifier in identifiers {
                do {
                    let webExtension = try await read(identifier)
                    if store.state(for: identifier)?.isEnabled ?? true {
                        try load(webExtension, identifier: identifier)
                    }
                } catch {
                    Logger.extensions.error("Extension non chargée : \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Active ou désactive l'extension installée `identifier` : chargée, ou déchargée ; retenu pour les prochains
    /// lancements.
    func setEnabled(_ isEnabled: Bool, identifier: String) async throws {
        if isEnabled, contexts[identifier] == nil {
            let webExtension = if let installed = installed[identifier] {
                installed
            } else {
                try await read(identifier)
            }
            try load(webExtension, identifier: identifier)
        } else if !isEnabled {
            unload(identifier: identifier)
        }
        var state = store.state(for: identifier) ?? ExtensionState()
        state.isEnabled = isEnabled
        store.setState(state, for: identifier)
    }

    /// Vrai si l'extension `identifier` est active (chargée au lancement).
    func isEnabled(_ identifier: String) -> Bool {
        store.state(for: identifier)?.isEnabled ?? true
    }

    /// Désinstalle l'extension `identifier` : déchargée, ses données (stockage) effacées, son dossier supprimé (une
    /// extension Safari reste dans son app), ses décisions oubliées.
    func uninstall(identifier: String) async {
        unload(identifier: identifier)
        let webExtensionIdentifier = webExtensionIdentifier(for: identifier)
        let types: Set<WKWebExtension.DataType> = [.local, .session, .synchronized]
        let records = await controller.dataRecords(ofTypes: types).filter { $0.uniqueIdentifier == webExtensionIdentifier }
        if !records.isEmpty {
            await controller.removeData(ofTypes: types, from: records)
        }
        let isFolder = store.state(for: identifier)?.appExtensionPath == nil
        if isFolder, let directory, ExtensionInstallDirectory.isValidIdentifier(identifier) {
            let folder = directory.appendingPathComponent(identifier, isDirectory: true)
            if FileManager.default.fileExists(atPath: folder.path) {
                do {
                    try FileManager.default.removeItem(at: folder)
                } catch {
                    Logger.extensions.error("Dossier d'extension non supprimé : \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        store.removeState(for: identifier)
        forget(identifier)
        Logger.extensions.info("Extension désinstallée (\(identifier, privacy: .public))")
    }

    /// Ouvre `url` dans un nouvel onglet de la fenêtre de navigation (jamais privée) et l'amène devant : liens des
    /// réglages vers les boutiques d'extensions. Faux sans fenêtre de navigation ouverte.
    @discardableResult
    func openInBrowser(_ url: URL) -> Bool {
        guard let model = windows.browserWindows.compactMap(\.model).first(where: { !$0.session.isPrivate }) else {
            return false
        }
        openTab(url, in: model, after: nil, isActive: true, isPinned: false)
        windows.adapter(for: model)?.owner?.nsWindow?.makeKeyAndOrderFront(nil)
        return true
    }

    /// Ouvre la page d'options de l'extension chargée `identifier` dans un nouvel onglet ; faux sans page d'options ou
    /// sans fenêtre de navigation.
    @discardableResult
    func openOptionsPage(identifier: String) -> Bool {
        guard let context = contexts[identifier], let url = context.optionsPageURL,
              let model = browserWindow(for: nil, context: context)
        else {
            return false
        }
        openTab(url, in: model, after: nil, isActive: true, isPinned: false)
        windows.adapter(for: model)?.owner?.nsWindow?.makeKeyAndOrderFront(nil)
        return true
    }
}
