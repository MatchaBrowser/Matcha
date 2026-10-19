import CryptoKit
import Foundation
import OSLog
import WebKit

/// Packages of extensions installed from a file (`SYNC.md` § 2.5 and § 4.7): the archive of the installed folder,
/// encrypted with its own key, uploaded before the record that references it; a new version has a new package, the
/// old one is deleted afterwards.
extension ExtensionSyncAdapter {
    /// 20 MiB at most: beyond that, the extension travels without its package (the other Mac shows it as “to
    /// reinstall”).
    nonisolated static let maximumPackageSize = 20 * 1024 * 1024

    /// Before a sync: uploads the package of extensions installed from a file that have none for their version, then
    /// installs the received updates that ask for no additional permission or website.
    func preparePackages(using transport: any SyncTransport) async {
        guard transport.supportsBlobs, let directory = manager.directory else {
            return
        }
        for identifier in manager.installedIdentifiers where manager.store.state(for: identifier)?.appExtensionPath == nil {
            let version = manager.installed[identifier]?.version
            if let known = synced.packages[identifier], version == nil || known.version == version {
                continue
            }
            do {
                let folder = directory.appendingPathComponent(identifier, isDirectory: true)
                guard let (package, sealed) = try await Self.sealPackage(of: folder, version: version, fileName: "\(identifier).zip") else {
                    Logger.sync.notice("Paquet d'extension trop gros : il ne voyage pas")
                    continue
                }
                try await transport.putBlob(sealed, id: package.blobID)
                if let old = synced.packages[identifier]?.blobID {
                    synced.obsoleteBlobs.append(old)
                }
                synced.packages[identifier] = package
            } catch {
                Logger.sync.error("Paquet d'extension non envoyé : \(error.localizedDescription, privacy: .public)")
            }
        }
        await installUpdates(using: transport)
    }

    /// After a sync: deletes from the server the replaced packages or those of uninstalled extensions.
    func deleteObsoletePackages(using transport: any SyncTransport) async {
        let installed = Set(manager.installedIdentifiers)
        for (identifier, package) in synced.packages where !installed.contains(identifier) {
            synced.packages[identifier] = nil
            synced.obsoleteBlobs.append(package.blobID)
        }
        for id in synced.obsoleteBlobs {
            do {
                try await transport.deleteBlob(id: id)
                synced.obsoleteBlobs.removeAll { $0 == id }
            } catch {
                Logger.sync.error("Ancien paquet d'extension non supprimé : \(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }

    /// Package downloaded, decrypted and verified (digest, size), written under its name in a temporary folder.
    func downloadPackage(_ package: SyncedPackage, using transport: any SyncTransport) async throws -> URL {
        let sealed = try await transport.blob(id: package.blobID)
        let data = try SyncCrypto.decryptBlob(sealed, id: package.blobID, key: SymmetricKey(data: package.blobKey))
        guard data.count == package.size, Self.sha256(of: data) == package.sha256.lowercased() else {
            throw SyncCryptoError.unreadable
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SyncedExtension-\(UUID().uuidString)",
            isDirectory: true,
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = URL(filePath: package.fileName).lastPathComponent
        let file = folder.appendingPathComponent(name.isEmpty || name.hasPrefix(".") ? "extension.zip" : name)
        try data.write(to: file)
        return file
    }

    /// Received updates of extensions installed here (`apply`): installed if they ask for no additional permission or
    /// website; otherwise they stay offered, and the permissions screen will come back.
    private func installUpdates(using transport: any SyncTransport) async {
        let installed = Set(manager.installedIdentifiers)
        for (identifier, fields) in synced.offers where installed.contains(identifier) {
            guard let package = SyncedPackage(source: fields.source, version: fields.version) else {
                continue
            }
            do {
                let file = try await downloadPackage(package, using: transport)
                defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
                let candidate = try await installer.prepare(fileAt: file)
                guard candidate.identifier == identifier, !asksForMore(candidate, than: identifier) else {
                    installer.discard(candidate)
                    continue
                }
                let allowsPrivateWindows = manager.store.state(for: identifier)?.hasAccessToPrivateData ?? false
                try await installer.install(candidate, allowsPrivateWindows: allowsPrivateWindows)
                synced.packages[identifier] = package
                synced.offers[identifier] = nil
            } catch SyncTransportError.blobNotFound {
                // Not arrived yet: at the next sync.
                continue
            } catch {
                Logger.sync.error("Mise à jour d'extension reçue non installée : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// True if `candidate` asks for a permission or a website that the installed version did not ask for.
    func asksForMore(_ candidate: ExtensionInstallCandidate, than identifier: String) -> Bool {
        guard let current = manager.installed[identifier] else {
            return true
        }
        let permissions = Set(candidate.webExtension.requestedPermissions).subtracting(current.requestedPermissions)
        let patterns = Set(candidate.webExtension.requestedPermissionMatchPatterns.map(\.string))
            .subtracting(current.requestedPermissionMatchPatterns.map(\.string))
        return !permissions.isEmpty || !patterns.isEmpty
    }

    /// Archive of the folder, encrypted with a new key, off the main thread; nil beyond 20 MiB.
    nonisolated static func sealPackage(of folder: URL, version: String?, fileName: String) async throws -> (SyncedPackage, Data)? {
        try await Task.detached(priority: .utility) {
            let archive = try ZipWriter.archive(folder: folder)
            guard archive.count <= maximumPackageSize else {
                return nil
            }
            let key = SymmetricKey(size: .bits256)
            let id = UUID()
            let sealed = try SyncCrypto.encryptBlob(archive, id: id, key: key)
            let package = SyncedPackage(
                version: version,
                blobID: id,
                blobKey: key.withUnsafeBytes { Data($0) },
                sha256: sha256(of: archive),
                size: archive.count,
                fileName: fileName,
            )
            return (package, sealed)
        }.value
    }

    nonisolated static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
