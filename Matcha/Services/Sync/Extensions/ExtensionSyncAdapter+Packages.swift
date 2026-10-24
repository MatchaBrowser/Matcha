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

    /// Before a sync: uploads the package of extensions installed from a file that have none for their version. A
    /// received update is never installed here: it waits for the user's click (`SYNC.md` § 2.5).
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
                    Logger.sync.notice("Extension package too large: not synced")
                    continue
                }
                try await transport.putBlob(sealed, id: package.blobID)
                if let old = synced.packages[identifier]?.blobID {
                    synced.obsoleteBlobs.append(old)
                }
                synced.packages[identifier] = package
            } catch {
                Logger.sync.error("Extension package not sent: \(error.logSummary, privacy: .public)")
            }
        }
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
                Logger.sync.error("Old extension package not deleted: \(error.logSummary, privacy: .public)")
                return
            }
        }
    }

    /// Package downloaded, decrypted and verified (digest, size), written under its name in a temporary folder.
    func downloadPackage(_ package: SyncedPackage, using transport: any SyncTransport) async throws -> URL {
        let sealed = try await transport.blob(id: package.blobID)
        return try await Self.openPackage(sealed, package)
    }

    /// Decrypts and checks `sealed`, then writes it to a temporary folder, off the main thread (up to 20 MiB, audit C4).
    @concurrent
    nonisolated static func openPackage(_ sealed: Data, _ package: SyncedPackage) async throws -> URL {
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

    /// Archive of the folder, encrypted with a new key, off the main thread; nil beyond 20 MiB.
    @concurrent
    nonisolated static func sealPackage(of folder: URL, version: String?, fileName: String) async throws -> (SyncedPackage, Data)? {
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
    }

    nonisolated static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
