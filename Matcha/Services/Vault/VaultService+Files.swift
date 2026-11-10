import CryptoKit
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Files of the vault (`VAULT.md` § 6): cut into chunks of 16 MiB, each one encrypted with the file's key and sent as a
/// package; downloaded when opened, checked, and written in clear only in a temporary folder that the lock empties.
extension VaultService {
    /// 100 MiB at most per file (R6).
    static let maximumFileBytes = 100 * 1024 * 1024
    /// Packages no longer cited are deleted after 30 days (`VAULT.md` § 6).
    static let obsoleteBlobLifetime: TimeInterval = 30 * 24 * 3600

    /// The folder where opened files are written, emptied at the lock and at quit.
    var openedFilesFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MatchaVault", isDirectory: true)
    }

    /// Encrypts and sends a file; returns its entry for the item's details. The packages go before the item that cites
    /// them (`SYNC.md` § 4.7).
    func uploadFile(at url: URL) async throws -> VaultEntry {
        guard let account, let client = account.client else {
            throw VaultError.unavailable
        }
        let data = try Self.read(url)
        let (fileID, key) = (UUID(), SymmetricKey(size: .bits256))
        let count = VaultManifestCrypto.chunkCount(ofSize: data.count)
        var chunks: [UUID] = []
        for index in 0 ..< count {
            let start = index * VaultManifestCrypto.fileChunkBytes
            let chunk = data[start ..< min(start + VaultManifestCrypto.fileChunkBytes, data.count)]
            let encrypted = try VaultManifestCrypto.encryptFileChunk(Data(chunk), fileID: fileID, index: index, count: count, key: key)
            let blobID = UUID()
            state.pendingBlobs.insert(blobID)
            saveState()
            try await client.putBlob(encrypted, id: blobID)
            chunks.append(blobID)
        }
        noteActivity()
        var entry = VaultEntry()
        entry.id = fileID.uuidString
        entry.set("name", url.lastPathComponent)
        entry.set("type", Self.mimeType(of: url))
        entry.set("size", integer: data.count)
        entry.set("sha256", SHA256.hash(data: data).hexString)
        entry.set("key", key.withUnsafeBytes { Data($0) }.base64EncodedString())
        entry.set("chunks", json: .array(chunks.map { .string($0.uuidString) }))
        entry.set("createdAt", SyncCoding.string(from: now()))
        return entry
    }

    /// Downloads, decrypts and checks a file of an item.
    func download(_ file: VaultEntry) async throws -> Data {
        guard let account, let client = account.client else {
            throw VaultError.unavailable
        }
        guard let fileID = UUID(uuidString: file.id), let keyData = Data(base64Encoded: file.string("key")), keyData.count == 32,
              case let .array(values)? = file.value("chunks")
        else {
            throw SyncCryptoError.unreadable
        }
        let chunks = values.compactMap {
            if case let .string(text) = $0 {
                UUID(uuidString: text)
            } else {
                nil
            }
        }
        let key = SymmetricKey(data: keyData)
        var data = Data()
        for (index, blobID) in chunks.enumerated() {
            let encrypted = try await client.blob(id: blobID, limit: account.maxBlobBytes)
            data += try VaultManifestCrypto.decryptFileChunk(encrypted, fileID: fileID, index: index, count: chunks.count, key: key)
        }
        guard data.count == file.integer("size"), SHA256.hash(data: data).hexString == file.string("sha256") else {
            throw SyncCryptoError.unreadable
        }
        noteActivity()
        return data
    }

    /// Writes a file in the temporary folder to open it; the lock deletes it.
    func open(_ file: VaultEntry) async throws -> URL {
        let data = try await download(file)
        let folder = openedFilesFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = (file.string("name") as NSString).lastPathComponent
        let url = folder.appendingPathComponent(name.isEmpty ? "file" : name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Deletes the files opened in clear (`VAULT.md` § 6).
    func deleteOpenedFiles() {
        try? FileManager.default.removeItem(at: openedFilesFolder)
    }

    /// Notes the packages of files that left an item: deleted after 30 days if nothing cites them by then.
    func noteObsoleteFiles(removed: [VaultEntry]) {
        for file in removed {
            if case let .array(values)? = file.value("chunks") {
                for case let .string(text) in values {
                    if let id = UUID(uuidString: text) {
                        state.obsoleteBlobs[id] = now()
                    }
                }
            }
        }
    }

    /// Deletes the packages no longer cited for 30 days, unless a version of the state in force cites them again.
    func deleteObsoleteBlobs() async {
        guard let client = account?.client, let session else {
            return
        }
        var due = Set(state.obsoleteBlobs.filter { now().timeIntervalSince($0.value) > Self.obsoleteBlobLifetime }.map(\.key))
        guard !due.isEmpty else {
            return
        }
        for (id, held) in state.items {
            for file in (try? session.codec.open(held.sealed, id: id).content.details.files) ?? [] {
                if case let .array(values)? = file.value("chunks") {
                    for case let .string(text) in values {
                        if let blob = UUID(uuidString: text), due.remove(blob) != nil {
                            state.obsoleteBlobs[blob] = nil
                        }
                    }
                }
            }
        }
        for id in due {
            do {
                try await client.deleteBlob(id: id)
                state.obsoleteBlobs[id] = nil
            } catch {
                Logger.vault.error("Obsolete vault package not deleted: \(error.logSummary, privacy: .public)")
                break
            }
        }
        saveState()
    }

    private static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else {
            throw VaultError.itemTooLarge
        }
        return data
    }

    private static func mimeType(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.preferredMIMEType) ?? "application/octet-stream"
    }
}
