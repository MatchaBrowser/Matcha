import Foundation
import OSLog
import WebKit

/// Installed extensions (tasks 6.3 and 6.4): those of the extensions folder and the Safari extensions of apps, read at
/// launch, loaded if they are enabled; enabling, disabling, uninstalling, options page.
extension ExtensionManager {
    /// Identifiers of the installed extensions: folders of `directory`, then the remembered Safari extensions of apps.
    var installedIdentifiers: [String] {
        let folders = directory.map { ExtensionInstallDirectory.installedExtensions(in: $0).map(\.identifier) } ?? []
        return folders + store.appExtensions.map(\.identifier).filter { !folders.contains($0) }
    }

    /// Reads the installed extensions in the background and loads the enabled ones. No effect on a second call.
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

    /// Enables or disables the installed extension `identifier`: loaded, or unloaded; remembered for the next launches.
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

    /// True if extension `identifier` is enabled (loaded at launch).
    func isEnabled(_ identifier: String) -> Bool {
        store.state(for: identifier)?.isEnabled ?? true
    }

    /// Uninstalls extension `identifier`: unloaded, its data (storage) erased, its folder deleted (a Safari extension
    /// stays in its app), its decisions forgotten.
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

    /// Opens `url` in a new tab of the browser window (never private) and brings it to the front: links from the
    /// settings to the extension stores. False with no browser window open.
    @discardableResult
    func openInBrowser(_ url: URL) -> Bool {
        guard let model = windows.browserWindows.compactMap(\.model).first(where: { !$0.session.isPrivate }) else {
            return false
        }
        openTab(url, in: model, after: nil, isActive: true, isPinned: false)
        windows.adapter(for: model)?.owner?.nsWindow?.makeKeyAndOrderFront(nil)
        return true
    }

    /// Opens the options page of the loaded extension `identifier` in a new tab; false without an options page or
    /// without a browser window.
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
