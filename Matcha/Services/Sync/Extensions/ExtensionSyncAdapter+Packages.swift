import CryptoKit
import Foundation
import OSLog
import WebKit

/// Paquets des extensions installées depuis un fichier (`SYNC.md` § 2.5 et § 4.7) : l'archive du dossier installé,
/// chiffrée par sa propre clé, envoyée avant l'enregistrement qui la cite ; une nouvelle version a un nouveau paquet,
/// l'ancien est supprimé ensuite.
extension ExtensionSyncAdapter {
    /// 20 Mio au plus : au-delà, l'extension voyage sans son paquet (l'autre Mac la montre « à réinstaller »).
    nonisolated static let maximumPackageSize = 20 * 1024 * 1024

    /// Avant une synchro : envoie le paquet des extensions installées depuis un fichier qui n'en ont pas pour leur
    /// version, puis installe les mises à jour reçues qui ne demandent ni permission ni site de plus.
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

    /// Après une synchro : supprime du serveur les paquets remplacés ou ceux des extensions désinstallées.
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

    /// Paquet téléchargé, déchiffré et vérifié (empreinte, taille), écrit sous son nom dans un dossier temporaire.
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

    /// Mises à jour reçues d'extensions installées ici (`apply`) : installées si elles ne demandent ni permission ni site
    /// de plus ; sinon elles restent proposées, et l'écran des permissions reviendra.
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
                // Pas encore arrivé : à la prochaine synchro.
                continue
            } catch {
                Logger.sync.error("Mise à jour d'extension reçue non installée : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Vrai si `candidate` demande une permission ou un site que la version installée ne demandait pas.
    func asksForMore(_ candidate: ExtensionInstallCandidate, than identifier: String) -> Bool {
        guard let current = manager.installed[identifier] else {
            return true
        }
        let permissions = Set(candidate.webExtension.requestedPermissions).subtracting(current.requestedPermissions)
        let patterns = Set(candidate.webExtension.requestedPermissionMatchPatterns.map(\.string))
            .subtracting(current.requestedPermissionMatchPatterns.map(\.string))
        return !permissions.isEmpty || !patterns.isEmpty
    }

    /// Archive du dossier, chiffrée par une nouvelle clé, hors du fil principal ; nil au-delà de 20 Mio.
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
