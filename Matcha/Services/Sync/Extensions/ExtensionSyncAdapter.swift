import Foundation
import OSLog
import WebKit

/// Extensions de Matcha vues par la synchro (tâche 7.4, `SYNC.md` § 2.5). Une extension installée ici suit les réglages
/// reçus (active, fenêtres privées, bouton, permissions) ; une extension reçue qui n'est pas installée n'est jamais
/// installée d'office : elle attend sous « Depuis vos autres Mac » (`SyncedExtensions.offers`). Désinstallée sur un
/// Mac, elle l'est partout.
@MainActor
final class ExtensionSyncAdapter {
    let manager: ExtensionManager
    let synced: SyncedExtensions
    let installer: ExtensionInstaller
    /// Transport de la synchro en cours, pour télécharger un paquet proposé ; nil sans synchro.
    var transport: (any SyncTransport)?

    init(manager: ExtensionManager, synced: SyncedExtensions, installer: ExtensionInstaller? = nil) {
        self.manager = manager
        self.synced = synced
        self.installer = installer ?? ExtensionInstaller(manager: manager)
    }

    /// Extensions installées sur ce Mac, par identifiant.
    func fields() -> [String: SyncExtensionFields] {
        var result: [String: SyncExtensionFields] = [:]
        for identifier in manager.installedIdentifiers {
            let state = currentState(of: identifier)
            let webExtension = manager.installed[identifier]
            if let name = webExtension?.displayName, synced.names[identifier] != name {
                synced.names[identifier] = name
            }
            result[identifier] = SyncExtensionFields(
                identifier: identifier,
                name: webExtension?.displayName ?? synced.names[identifier] ?? identifier,
                version: webExtension?.version ?? synced.packages[identifier]?.version,
                source: source(of: identifier, state: state),
                isEnabled: state.isEnabled,
                allowsPrivateWindows: state.hasAccessToPrivateData,
                showsButton: state.showsButton ?? true,
                grantedPermissions: Self.expirations(state.grantedPermissions),
                deniedPermissions: Self.expirations(state.deniedPermissions),
                grantedMatchPatterns: Self.expirations(state.grantedMatchPatterns),
                deniedMatchPatterns: Self.expirations(state.deniedMatchPatterns),
            )
        }
        return result
    }

    /// Extension reçue : réglages appliqués si elle est installée ici (un nouveau paquet attend la prochaine synchro,
    /// `updatePackages`), sinon proposée, sauf si l'utilisateur l'a ignorée.
    func apply(_ fields: SyncExtensionFields) {
        let identifier = fields.identifier
        guard ExtensionInstallDirectory.isValidIdentifier(identifier) else {
            return
        }
        guard manager.installedIdentifiers.contains(identifier) else {
            if !synced.ignored.contains(identifier) {
                synced.offers[identifier] = fields
            }
            return
        }
        applySettings(fields)
        // Nouveau paquet d'une extension installée ici : installé à la prochaine synchro s'il ne demande rien de plus.
        let package = SyncedPackage(source: fields.source, version: fields.version)
        if let package, let known = synced.packages[identifier], known.blobID != package.blobID {
            synced.offers[identifier] = fields
        }
    }

    /// Extension désinstallée sur un autre Mac : désinstallée ici aussi, ses données avec.
    func remove(identifier: String) {
        synced.offers[identifier] = nil
        guard manager.installedIdentifiers.contains(identifier) else {
            return
        }
        Task { [manager] in
            await manager.uninstall(identifier: identifier)
        }
    }

    /// N'est plus proposée sur ce Mac.
    func ignore(_ identifier: String) {
        synced.offers[identifier] = nil
        synced.ignored.insert(identifier)
    }

    // MARK: Réglages

    private func applySettings(_ fields: SyncExtensionFields) {
        let identifier = fields.identifier
        var state = manager.store.state(for: identifier) ?? ExtensionState()
        let wasEnabled = state.isEnabled
        let hadPrivateAccess = state.hasAccessToPrivateData
        state.isEnabled = fields.isEnabled
        state.hasAccessToPrivateData = fields.allowsPrivateWindows
        state.showsButton = fields.showsButton ? nil : false
        state.grantedPermissions = Self.dates(fields.grantedPermissions)
        state.deniedPermissions = Self.dates(fields.deniedPermissions)
        state.grantedMatchPatterns = Self.dates(fields.grantedMatchPatterns)
        state.deniedMatchPatterns = Self.dates(fields.deniedMatchPatterns)
        manager.store.setState(state, for: identifier)
        if let context = manager.contexts[identifier] {
            state.apply(to: context)
        }
        if hadPrivateAccess != fields.allowsPrivateWindows {
            manager.setAccessToPrivateData(fields.allowsPrivateWindows, identifier: identifier)
        }
        manager.buttonsDidChange()
        if wasEnabled != fields.isEnabled {
            Task { [manager] in
                do {
                    try await manager.setEnabled(fields.isEnabled, identifier: identifier)
                } catch {
                    Logger.sync.error("Extension reçue non chargée : \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Décisions actuelles : celles du contexte chargé, sinon celles retenues.
    private func currentState(of identifier: String) -> ExtensionState {
        let stored = manager.store.state(for: identifier) ?? ExtensionState()
        guard let context = manager.contexts[identifier] else {
            return stored
        }
        return manager.state(of: context, identifier: identifier, isEnabled: stored.isEnabled)
    }

    private func source(of identifier: String, state: ExtensionState) -> SyncExtensionSource {
        if let path = state.appExtensionPath {
            let appex = URL(filePath: path)
            let app = Self.app(containing: appex)
            return .appExtension(
                bundleIdentifier: Bundle(url: appex)?.bundleIdentifier ?? identifier,
                appBundleIdentifier: app.flatMap { Bundle(url: $0)?.bundleIdentifier },
                appName: app.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") },
            )
        }
        return synced.packages[identifier]?.source ?? .package(blobID: nil, blobKey: nil, sha256: nil, size: nil, fileName: nil)
    }

    /// App qui contient le `.appex` (…/App.app/Contents/PlugIns/X.appex).
    static func app(containing appex: URL) -> URL? {
        var url = appex.deletingLastPathComponent()
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    /// Date d'expiration, nil sans expiration (`Date.distantFuture` dans `ExtensionState`).
    static func expirations(_ dates: [String: Date]) -> [String: Date?] {
        dates.mapValues { $0 >= .distantFuture ? nil : $0 }
    }

    static func dates(_ expirations: [String: Date?]) -> [String: Date] {
        expirations.mapValues { $0 ?? .distantFuture }
    }
}

extension ExtensionSyncAdapter {
    /// Synchro des extensions de l'app, avec ses réglages dans `Application Support/Sync/extensions.json`. Pendant les
    /// tests (unitaires et base de test), tout reste en mémoire.
    static let shared: ExtensionSyncAdapter = {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || UserDefaults.standard.bool(forKey: BrowserSession.inMemoryStoreKey)
        let url = isTesting ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sync/extensions.json")
        return ExtensionSyncAdapter(manager: .shared, synced: SyncedExtensions(url: url))
    }()
}
