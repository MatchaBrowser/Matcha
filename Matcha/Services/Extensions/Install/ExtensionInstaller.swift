import CryptoKit
import Foundation
import OSLog
import WebKit

/// Extension prête à installer, en attente de l'accord de l'utilisateur (écran des permissions, tâche 6.4).
struct ExtensionInstallCandidate: Identifiable {
    enum Source {
        /// Fichier ou dossier choisi : décompressé dans `staging`, manifeste dans `root`.
        case package(root: URL, staging: URL, fileName: String)
        /// Extension Safari d'une app, chargée sur place.
        case appExtension(SafariAppExtension)
    }

    let identifier: String
    let webExtension: WKWebExtension
    let source: Source
    /// Une extension de même identifiant est déjà installée : elle sera remplacée, ses données gardées.
    let isUpdate: Bool

    var id: String {
        identifier
    }

    /// Ce que l'extension pourra faire, pour l'écran des permissions.
    var summary: [ExtensionPermissionSummary.Line] {
        ExtensionPermissionSummary.lines(
            permissions: Set(webExtension.requestedPermissions.map(\.rawValue)),
            hosts: webExtension.requestedPermissionMatchPatterns.map { $0.matchesAllHosts ? nil : $0.host },
        )
    }
}

/// Installe les extensions (tâche 6.4) : un fichier (`.crx`, `.xpi`, `.zip`) ou un dossier décompressé est préparé dans
/// un dossier temporaire, puis, une fois accepté, déplacé dans `Application Support/Extensions/<identifiant>/` ; une
/// extension Safari d'app reste dans son app. À l'installation, les permissions et les sites demandés sont accordés
/// (l'utilisateur vient de les voir), les fenêtres privées seulement s'il l'a choisi ; puis l'extension est chargée.
@MainActor
final class ExtensionInstaller {
    let manager: ExtensionManager
    private let stagingRoot: URL

    init(manager: ExtensionManager, stagingRoot: URL? = nil) {
        self.manager = manager
        self.stagingRoot = stagingRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExtensionInstall",
            isDirectory: true,
        )
    }

    /// Prépare l'extension du fichier ou du dossier `url`.
    func prepare(fileAt url: URL) async throws -> ExtensionInstallCandidate {
        let staging = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try FileManager.default.copyItem(at: url, to: staging)
            } else {
                let data = try Data(contentsOf: url)
                try ZipArchive(data: ExtensionPackage.zipData(from: data)).extract(to: staging)
            }
            let root = try Self.manifestFolder(in: staging)
            guard let file = ExtensionManifestFile(folder: root) else {
                throw ExtensionInstallError.noManifest
            }
            let identifier = ExtensionIdentifier.forPackage(file) ?? Self.fallbackIdentifier(for: file.name ?? url.lastPathComponent)
            let webExtension = try await WKWebExtension(resourceBaseURL: root)
            return ExtensionInstallCandidate(
                identifier: identifier,
                webExtension: webExtension,
                source: .package(root: root, staging: staging, fileName: url.lastPathComponent),
                isUpdate: manager.installedIdentifiers.contains(identifier),
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw ExtensionInstallError(error)
        }
    }

    /// Prépare l'extension Safari d'une app.
    func prepare(_ appExtension: SafariAppExtension) async throws -> ExtensionInstallCandidate {
        guard let identifier = ExtensionIdentifier.forAppExtension(bundleIdentifier: appExtension.bundleIdentifier),
              let bundle = Bundle(url: appExtension.extensionURL)
        else {
            throw ExtensionInstallError.unreadable
        }
        do {
            let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            return ExtensionInstallCandidate(
                identifier: identifier,
                webExtension: webExtension,
                source: .appExtension(appExtension),
                isUpdate: manager.installedIdentifiers.contains(identifier),
            )
        } catch {
            throw ExtensionInstallError(error)
        }
    }

    /// Installe `candidate` (accepté par l'utilisateur) et le charge ; une version déjà installée est remplacée.
    func install(_ candidate: ExtensionInstallCandidate, allowsPrivateWindows: Bool) async throws {
        let identifier = candidate.identifier
        manager.unload(identifier: identifier)
        var state = manager.store.state(for: identifier) ?? ExtensionState()
        switch candidate.source {
        case let .package(root, staging, _):
            guard let directory = manager.directory else {
                throw ExtensionInstallError.unreadable
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(identifier, isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: root, to: destination)
            try? FileManager.default.removeItem(at: staging)
            state.appExtensionPath = nil
        case let .appExtension(appExtension):
            state.appExtensionPath = appExtension.extensionURL.path
        }
        for permission in candidate.webExtension.requestedPermissions {
            state.grantedPermissions[permission.rawValue] = .distantFuture
            state.deniedPermissions[permission.rawValue] = nil
        }
        for pattern in candidate.webExtension.requestedPermissionMatchPatterns {
            state.grantedMatchPatterns[pattern.string] = .distantFuture
            state.deniedMatchPatterns[pattern.string] = nil
        }
        state.hasAccessToPrivateData = allowsPrivateWindows
        state.isEnabled = true
        manager.store.setState(state, for: identifier)
        let webExtension = try await manager.read(identifier)
        try manager.load(webExtension, identifier: identifier)
        let kind = candidate.isUpdate ? "mise à jour" : "installée"
        Logger.extensions.info("Extension \(kind, privacy: .public) (\(identifier, privacy: .public))")
    }

    /// Abandonne `candidate` (refusé) : son dossier temporaire est effacé.
    func discard(_ candidate: ExtensionInstallCandidate) {
        if case let .package(_, staging, _) = candidate.source {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    /// Dossier du manifeste : `folder` lui-même, ou son unique sous-dossier (archive d'un dossier).
    static func manifestFolder(in folder: URL) throws -> URL {
        let manifest = ExtensionInstallDirectory.manifestName
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(manifest).path) {
            return folder
        }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles,
        )) ?? []
        let folders = children.filter {
            $0.lastPathComponent != "__MACOSX" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard folders.count == 1, FileManager.default.fileExists(atPath: folders[0].appendingPathComponent(manifest).path) else {
            throw ExtensionInstallError.noManifest
        }
        return folders[0]
    }

    /// Identifiant d'une extension dont le nom n'a aucune lettre ASCII : `extension-` et le début de son empreinte.
    static func fallbackIdentifier(for name: String) -> String {
        let digest = SHA256.hash(data: Data(name.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "extension-\(digest)"
    }
}
