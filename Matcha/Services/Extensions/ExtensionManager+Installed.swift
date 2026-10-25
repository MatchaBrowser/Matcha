import Foundation
import OSLog
import WebKit

/// Installed extensions (tasks 6.3 and 6.4): those of the extensions folder and the Safari extensions of apps, read at
/// launch, loaded if they are enabled; enabling, disabling, uninstalling, options page.
extension ExtensionManager {
    /// Runs `work` once the operations already started on extension `identifier` have ended (review EX21): an
    /// uninstallation received from another Mac or a change of state never interleaves with an installation's waits.
    func serialized(_ identifier: String, _ work: @escaping @MainActor () async throws -> Void) async throws {
        let previous = operations[identifier]
        let task = Task { @MainActor in
            await previous?.value
            try await work()
        }
        let marker = Task { @MainActor in _ = try? await task.value }
        operations[identifier] = marker
        defer {
            if operations[identifier] == marker {
                operations[identifier] = nil
            }
        }
        try await task.value
    }

    /// Identifiers of the installed extensions: folders of `directory`, then the remembered Safari extensions of apps.
    var installedIdentifiers: [String] {
        installedFolders + store.appExtensions.map(\.identifier).filter { !installedFolders.contains($0) }
    }

    /// Reads the installed extensions in the background and loads the enabled ones. No effect on a second call.
    func start() {
        guard !isStarted, directory != nil else {
            return
        }
        isStarted = true
        refreshInstalledFolders()
        let identifiers = installedIdentifiers
        Task {
            for identifier in identifiers {
                do {
                    let webExtension = try await read(identifier)
                    if store.state(for: identifier)?.isEnabled ?? true {
                        try load(webExtension, identifier: identifier)
                    }
                } catch {
                    Logger.extensions.error("Extension not loaded: \(error.logSummary, privacy: .public)")
                }
            }
        }
    }

    /// Enables or disables the installed extension `identifier`: loaded, or unloaded; remembered for the next launches.
    /// Never during another operation on it (review EX21).
    func setEnabled(_ isEnabled: Bool, identifier: String) async throws {
        try await serialized(identifier) { [self] in
            try await performSetEnabled(isEnabled, identifier: identifier)
        }
    }

    private func performSetEnabled(_ isEnabled: Bool, identifier: String) async throws {
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

    /// Uninstalls extension `identifier`: unloaded, its data (storage) erased, its folder deleted off the main thread
    /// (a Safari extension stays in its app), its decisions forgotten. Never during another operation on it (EX21).
    func uninstall(identifier: String) async {
        try? await serialized(identifier) { [self] in
            await performUninstall(identifier: identifier)
        }
    }

    private func performUninstall(identifier: String) async {
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
            if FileManager.default.fileExists(atPath: folder.path), await !FileRemoval.remove(folder) {
                Logger.extensions.error("Extension folder not deleted")
            }
        }
        store.removeState(for: identifier)
        refreshInstalledFolders()
        forget(identifier)
        Logger.extensions.info("Extension uninstalled (\(identifier, privacy: .private))")
    }

    /// Opens `url` in a new tab of the browser window (never private) and brings it to the front: links from the
    /// settings to the extension stores. False with no browser window open.
    @discardableResult
    func openInBrowser(_ url: URL) -> Bool {
        host?.openPage(url, for: nil) ?? false
    }

    /// Opens the options page of the loaded extension `identifier` in a new tab; false without an options page or
    /// without a browser window.
    @discardableResult
    func openOptionsPage(identifier: String) -> Bool {
        guard let context = contexts[identifier], let url = context.optionsPageURL else {
            return false
        }
        return host?.openPage(url, for: context) ?? false
    }
}
