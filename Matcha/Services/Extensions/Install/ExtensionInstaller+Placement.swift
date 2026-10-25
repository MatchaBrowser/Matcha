import Foundation
import WebKit

/// Where a file installs (audit E1): over the installed extension from the same verified publisher (an update, which
/// keeps its data); in place of an installed extension with the same name but no proof of the same developer (a
/// replacement, which erases its data); otherwise as another extension, under a new identifier.
///
/// A sync offer (`preferredIdentifier`, its identifier on your other Macs) for an extension installed here updates it,
/// even unsigned: the package is the one this extension has on your other Macs, and the user confirms it on this Mac
/// (`SYNC.md` § 2.5). Only a `.crx` signed by another publisher replaces it (review EX2).
extension ExtensionInstaller {
    func placement(name: String?, publisher: String?, preferredIdentifier: String?) -> (String, ExtensionInstallCandidate.Mode) {
        let installed = manager.installedIdentifiers.filter { manager.store.state(for: $0)?.appExtensionPath == nil }
        if let offered = preferredIdentifier, installed.contains(offered) {
            let installedPublisher = manager.store.state(for: offered)?.publisher
            if let publisher, let installedPublisher, publisher != installedPublisher {
                return (ExtensionIdentifier.random(), .replacement(identifier: offered, previousVersion: installedVersion(of: offered)))
            }
            return (offered, .update(previousVersion: installedVersion(of: offered)))
        }
        if let publisher, let match = installed.first(where: { manager.store.state(for: $0)?.publisher == publisher }) {
            return (match, .update(previousVersion: installedVersion(of: match)))
        }
        let identifier = preferredIdentifier.flatMap { identifier in
            ExtensionInstallDirectory.isValidIdentifier(identifier) && !identifier.hasPrefix("safari-")
                && !manager.installedIdentifiers.contains(identifier) ? identifier : nil
        } ?? ExtensionIdentifier.random()
        if let name, let match = installed.first(where: { installedName(of: $0)?.caseInsensitiveCompare(name) == .orderedSame }) {
            return (identifier, .replacement(identifier: match, previousVersion: installedVersion(of: match)))
        }
        return (identifier, .new)
    }

    /// For an update: what the installed version couldn't do, and whether it had private windows.
    func describeUpdate(_ candidate: inout ExtensionInstallCandidate) async {
        guard candidate.isUpdate else {
            return
        }
        var current = manager.installed[candidate.identifier]
        if current == nil {
            current = try? await manager.read(candidate.identifier)
        }
        candidate.addedSummary = ExtensionInstallCandidate.summary(of: candidate.webExtension, minus: current)
        candidate.allowedPrivateWindows = manager.store.state(for: candidate.identifier)?.hasAccessToPrivateData ?? false
    }

    func installedVersion(of identifier: String) -> String? {
        manager.store.state(for: identifier)?.version ?? manager.installed[identifier]?.version
            ?? manifest(of: identifier)?.manifest["version"] as? String
    }

    private func installedName(of identifier: String) -> String? {
        manager.installed[identifier]?.displayName ?? manifest(of: identifier)?.name
    }

    private func manifest(of identifier: String) -> ExtensionManifestFile? {
        manager.directory.flatMap { ExtensionManifestFile(folder: $0.appendingPathComponent(identifier, isDirectory: true)) }
    }
}
