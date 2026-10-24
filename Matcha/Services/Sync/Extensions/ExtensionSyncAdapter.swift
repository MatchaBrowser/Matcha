import Foundation
import OSLog
import WebKit

/// Matcha's extensions as seen by sync (`SYNC.md` § 2.5). An extension installed here follows the received settings
/// (enabled, button), but received permissions can only reduce this Mac's, and access to private windows can only be
/// removed. No code is ever installed without a click here: a received extension that is not installed, or a new
/// package of an installed one, waits under “From Your Other Macs” (`SyncedExtensions.offers`). Uninstalled on one
/// Mac, it is uninstalled everywhere.
@MainActor
final class ExtensionSyncAdapter {
    let manager: ExtensionManager
    let synced: SyncedExtensions
    let installer: ExtensionInstaller
    /// Transport of the current sync, to download an offered package; nil without sync.
    var transport: (any SyncTransport)?

    init(manager: ExtensionManager, synced: SyncedExtensions, installer: ExtensionInstaller? = nil) {
        self.manager = manager
        self.synced = synced
        self.installer = installer ?? ExtensionInstaller(manager: manager)
    }

    /// Extensions installed on this Mac, by identifier.
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

    /// Received extension: settings applied if it is installed here (a new package waits for the next sync,
    /// `updatePackages`), otherwise offered, unless the user ignored it.
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
        // New package of an extension installed here: offered, never installed by itself, unless this version was
        // ignored.
        guard let package = SyncedPackage(source: fields.source, version: fields.version),
              let known = synced.packages[identifier], known.blobID != package.blobID
        else {
            return
        }
        if synced.ignoredUpdates[identifier] != package.sha256 {
            synced.offers[identifier] = fields
        }
    }

    /// Extension uninstalled on another Mac: uninstalled here too, along with its data.
    func remove(identifier: String) {
        synced.offers[identifier] = nil
        guard manager.installedIdentifiers.contains(identifier) else {
            return
        }
        Task { [manager] in
            await manager.uninstall(identifier: identifier)
        }
    }

    /// No longer offered on this Mac; for an update of an installed extension, only this version (“Ignore This
    /// Version”): a later one is offered again.
    func ignore(_ identifier: String) {
        let offer = synced.offers.removeValue(forKey: identifier)
        if manager.installedIdentifiers.contains(identifier) {
            if let sha256 = offer?.source.sha256 {
                synced.ignoredUpdates[identifier] = sha256
            }
        } else {
            synced.ignored.insert(identifier)
        }
    }

    // MARK: Settings

    /// Enabled and button follow; permissions and sites only lose what the received record doesn't grant, and gain its
    /// refusals; access to private windows can be removed, never granted (`SYNC.md` § 2.5).
    private func applySettings(_ fields: SyncExtensionFields) {
        let identifier = fields.identifier
        var state = currentState(of: identifier)
        let wasEnabled = state.isEnabled
        let hadPrivateAccess = state.hasAccessToPrivateData
        state.isEnabled = fields.isEnabled
        state.hasAccessToPrivateData = hadPrivateAccess && fields.allowsPrivateWindows
        state.showsButton = fields.showsButton ? nil : false
        (state.grantedPermissions, state.deniedPermissions) = Self.reduced(
            granted: state.grantedPermissions,
            denied: state.deniedPermissions,
            receivedGranted: fields.grantedPermissions,
            receivedDenied: fields.deniedPermissions,
        )
        (state.grantedMatchPatterns, state.deniedMatchPatterns) = Self.reduced(
            granted: state.grantedMatchPatterns,
            denied: state.deniedMatchPatterns,
            receivedGranted: fields.grantedMatchPatterns,
            receivedDenied: fields.deniedMatchPatterns,
        )
        manager.store.setState(state, for: identifier)
        if let context = manager.contexts[identifier] {
            state.apply(to: context)
        }
        if hadPrivateAccess != state.hasAccessToPrivateData {
            manager.setAccessToPrivateData(state.hasAccessToPrivateData, identifier: identifier)
        }
        manager.toolbar.buttonsDidChange()
        if wasEnabled != fields.isEnabled {
            Task { [manager] in
                do {
                    try await manager.setEnabled(fields.isEnabled, identifier: identifier)
                } catch {
                    Logger.sync.error("Received extension not loaded: \(error.logSummary, privacy: .public)")
                }
            }
        }
    }

    /// This Mac's grants that the received record also grants, and its refusals plus the received ones: a grant made
    /// elsewhere is never added here (the extension asks again on this Mac). Pure.
    nonisolated static func reduced(
        granted: [String: Date],
        denied: [String: Date],
        receivedGranted: [String: Date?],
        receivedDenied: [String: Date?],
    ) -> (granted: [String: Date], denied: [String: Date]) {
        var newDenied = denied
        for (name, expiration) in receivedDenied where newDenied[name] == nil {
            newDenied[name] = expiration ?? .distantFuture
        }
        let newGranted = granted.filter { receivedGranted.keys.contains($0.key) && newDenied[$0.key] == nil }
        return (newGranted, newDenied)
    }

    /// Current decisions: those of the loaded context, otherwise the remembered ones.
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

    /// App that contains the `.appex` (…/App.app/Contents/PlugIns/X.appex).
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

    /// Expiration date, nil without expiration (`Date.distantFuture` in `ExtensionState`).
    static func expirations(_ dates: [String: Date]) -> [String: Date?] {
        dates.mapValues { $0 >= .distantFuture ? nil : $0 }
    }

    static func dates(_ expirations: [String: Date?]) -> [String: Date] {
        expirations.mapValues { $0 ?? .distantFuture }
    }
}
