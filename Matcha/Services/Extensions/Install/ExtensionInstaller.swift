import Foundation
import OSLog
import WebKit

/// Installs extensions (task 6.4): a file (`.crx`, `.xpi`, `.zip`) or an unpacked folder is prepared in a temporary
/// folder, then, once accepted, moved to `Application Support/Extensions/<identifier>/`; an app's Safari extension
/// stays in its app. On installation, the requested permissions and websites are granted (the user has just seen them),
/// private windows only if the user chose so; then the extension is loaded.
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

    /// Prepares the extension of the file or folder `url`. `preferredIdentifier`: the one it has on your other Macs
    /// (offer received by sync), used if it is new here.
    func prepare(fileAt url: URL, preferredIdentifier: String? = nil) async throws -> ExtensionInstallCandidate {
        let staging = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            // Off the main thread, without links, within size limits (audits E3 and E6).
            let publisher = try await ExtensionUnpacker.unpack(url, into: staging)
            let root = try Self.manifestFolder(in: staging)
            guard let file = ExtensionManifestFile(folder: root) else {
                throw ExtensionInstallError.noManifest
            }
            let webExtension = try await WKWebExtension(resourceBaseURL: root)
            let name = webExtension.displayName ?? file.name
            let (identifier, mode) = placement(name: name, publisher: publisher, preferredIdentifier: preferredIdentifier)
            var candidate = ExtensionInstallCandidate(
                identifier: identifier,
                webExtension: webExtension,
                source: .package(root: root, staging: staging, fileName: url.lastPathComponent),
                mode: mode,
                publisher: publisher,
            )
            await describeUpdate(&candidate)
            return candidate
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw ExtensionInstallError(error)
        }
    }

    /// Prepares an app's Safari extension: the app vouches for it, so installing it again is an update.
    func prepare(_ appExtension: SafariAppExtension) async throws -> ExtensionInstallCandidate {
        guard let identifier = ExtensionIdentifier.forAppExtension(bundleIdentifier: appExtension.bundleIdentifier),
              let bundle = Bundle(url: appExtension.extensionURL)
        else {
            throw ExtensionInstallError.unreadable
        }
        do {
            let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            let isInstalled = manager.installedIdentifiers.contains(identifier)
            var candidate = ExtensionInstallCandidate(
                identifier: identifier,
                webExtension: webExtension,
                source: .appExtension(appExtension),
                mode: isInstalled ? .update(previousVersion: installedVersion(of: identifier)) : .new,
            )
            await describeUpdate(&candidate)
            return candidate
        } catch {
            throw ExtensionInstallError(error)
        }
    }

    /// Installs `candidate` (accepted by the user) and loads it. An update replaces the installed version and keeps its
    /// data and the user's refusals (audit E2); a replacement then uninstalls the extension it replaces, data included
    /// (audit E1). If the new version can't be loaded, the previous one comes back, folder and decisions (audit E6).
    func install(_ candidate: ExtensionInstallCandidate, allowsPrivateWindows: Bool) async throws {
        let identifier = candidate.identifier
        let previous = manager.store.state(for: identifier)
        let wasLoaded = manager.contexts[identifier] != nil
        manager.unload(identifier: identifier)
        let swap = try placeFiles(of: candidate)
        do {
            manager.store.setState(
                state(for: candidate, previous: candidate.isUpdate ? previous : nil, allowsPrivateWindows: allowsPrivateWindows),
                for: identifier,
            )
            let installed = try await manager.read(identifier)
            try manager.load(installed, identifier: identifier)
        } catch {
            swap?.restore()
            if let previous {
                manager.store.setState(previous, for: identifier)
                if wasLoaded, let restored = try? await manager.read(identifier) {
                    _ = try? manager.load(restored, identifier: identifier)
                }
            } else {
                manager.store.removeState(for: identifier)
            }
            throw error
        }
        swap?.finish()
        if case let .replacement(replaced, _) = candidate.mode {
            await manager.uninstall(identifier: replaced)
        }
        let kind = switch candidate.mode {
        case .new: "installée"
        case .update: "mise à jour"
        case .replacement: "remplacée"
        }
        Logger.extensions.info("Extension \(kind, privacy: .public) (\(identifier, privacy: .private))")
    }

    /// Decisions of the installed version (audit E2: what it asks for, minus what the user refused).
    private func state(for candidate: ExtensionInstallCandidate, previous: ExtensionState?, allowsPrivateWindows: Bool) -> ExtensionState {
        var state = previous ?? ExtensionState()
        let webExtension = candidate.webExtension
        state.applyRequests(
            permissions: Set(webExtension.requestedPermissions.map(\.rawValue)),
            patterns: Set(webExtension.requestedPermissionMatchPatterns.map(\.string)),
            optionalPermissions: Set(webExtension.optionalPermissions.map(\.rawValue)),
            optionalPatterns: Set(webExtension.optionalPermissionMatchPatterns.map(\.string)),
        )
        if case let .appExtension(appExtension) = candidate.source {
            state.appExtensionPath = appExtension.extensionURL.path
            state.appExtensionIdentity = SafariExtensionFinder.safariIdentifier(ofAppExtensionAt: appExtension.extensionURL)
        } else {
            state.appExtensionPath = nil
            state.appExtensionIdentity = nil
        }
        state.hasAccessToPrivateData = allowsPrivateWindows
        state.isEnabled = true
        state.publisher = candidate.publisher ?? previous?.publisher
        state.version = webExtension.version
        return state
    }

    /// Puts the unpacked folder in place: the previous version is kept aside until the new one loads (`FolderSwap`).
    private func placeFiles(of candidate: ExtensionInstallCandidate) throws -> FolderSwap? {
        guard case let .package(root, staging, _) = candidate.source else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: staging) }
        guard let directory = manager.directory else {
            throw ExtensionInstallError.unreadable
        }
        return try FolderSwap(placing: root, at: directory.appendingPathComponent(candidate.identifier, isDirectory: true))
    }

    /// Discards `candidate` (refused): its temporary folder is erased.
    func discard(_ candidate: ExtensionInstallCandidate) {
        if case let .package(_, staging, _) = candidate.source {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    /// Folder of the manifest: `folder` itself, or its single subfolder (archive of a folder).
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
}
