import CryptoKit
import Foundation
import OSLog
import WebKit

/// Packages of extensions installed from a file (`SYNC.md` § 2.5 and § 4.7): the archive of the installed folder,
/// encrypted with its own key, noted as pending, uploaded before the record that references it; a new version has a new
/// package, the old one is deleted afterwards, and so is a package that no record cites once they have left (orphan,
/// review SY33).
extension ExtensionSyncAdapter {
    /// 20 MiB at most: beyond that, the extension travels without its package (the other Mac shows it as “to
    /// reinstall”).
    nonisolated static let maximumPackageSize = 20 * 1024 * 1024

    /// Before a sync: uploads the package of extensions installed from a file that have none for their version. A
    /// received update is never installed here: it waits for the user's click (`SYNC.md` § 2.5). A version too large
    /// isn't archived again; a refused upload waits, longer each time (review SY16).
    func preparePackages(using transport: any SyncTransport, now: Date = .now) async {
        guard Distribution.syncsExtensionPackages, transport.supportsBlobs, let directory = manager.directory else {
            return
        }
        for identifier in manager.installedIdentifiers where manager.store.state(for: identifier)?.appExtensionPath == nil {
            let version = manager.installed[identifier]?.version
            if let known = synced.packages[identifier], version == nil || known.version == version {
                continue
            }
            if let failure = synced.packageFailures[identifier], failure.version == version, !failure.allowsAttempt(at: now) {
                continue
            }
            do {
                let folder = directory.appendingPathComponent(identifier, isDirectory: true)
                guard let (package, sealed) = try await Self.sealPackage(of: folder, version: version, fileName: "\(identifier).zip") else {
                    Logger.sync.notice("Extension package too large: not synced")
                    synced.packageFailures[identifier] = SyncedPackageFailure(
                        version: version,
                        isTooLarge: true,
                        attempts: 1,
                        failedAt: now,
                    )
                    continue
                }
                // Noted first: sent, then lost before its record (quit, crash), it is found again and deleted.
                synced.pendingBlobs.insert(package.blobID)
                try await transport.putBlob(sealed, id: package.blobID)
                if let old = synced.packages[identifier]?.blobID {
                    synced.obsoleteBlobs.append(old)
                }
                synced.packages[identifier] = package
                synced.packageFailures[identifier] = nil
            } catch {
                Logger.sync.error("Extension package not sent: \(error.logSummary, privacy: .public)")
                let previous = synced.packageFailures[identifier].flatMap { $0.version == version ? $0 : nil }
                let isTooLarge = (error as? SyncServerError)?.code == SyncServerError.blobTooLarge
                synced.packageFailures[identifier] = SyncedPackageFailure(
                    version: version,
                    isTooLarge: isTooLarge,
                    attempts: (previous?.attempts ?? 0) + 1,
                    failedAt: now,
                )
            }
        }
    }

    /// After a sync: deletes from the server the replaced packages, those of uninstalled extensions and the orphans;
    /// never while an extension's record waits to leave, which may still cite them (`SYNC.md` § 4.7, review SY33). Once
    /// the records have left, a pending package that one cites is applied, any other is an orphan; the first sync after
    /// a launch finds those of a session that ended between the package and its record.
    func deleteObsoletePackages(using transport: any SyncTransport, recordsSent: Bool = true) async {
        guard recordsSent else {
            return
        }
        let installed = Set(manager.installedIdentifiers)
        for (identifier, package) in synced.packages where !installed.contains(identifier) {
            synced.packages[identifier] = nil
            synced.obsoleteBlobs.append(package.blobID)
        }
        if !synced.pendingBlobs.isEmpty {
            let cited = Set(synced.packages.values.map(\.blobID))
            let orphans = synced.pendingBlobs.subtracting(cited).subtracting(synced.obsoleteBlobs)
            synced.obsoleteBlobs.append(contentsOf: orphans.sorted { $0.uuidString < $1.uuidString })
            synced.pendingBlobs = []
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

    /// Archive of the folder, encrypted with a new key, off the main thread; nil beyond 20 MiB, known as soon as the
    /// archive passes it.
    @concurrent
    nonisolated static func sealPackage(of folder: URL, version: String?, fileName: String) async throws -> (SyncedPackage, Data)? {
        let archive: Data
        do {
            archive = try ZipWriter.archive(folder: folder, limit: maximumPackageSize)
        } catch ZipWriter.Failure.tooLarge {
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
