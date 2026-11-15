import CryptoKit
import Foundation

/// A bucket of the manifest, once opened (`VAULT.md` § 4.1): for each item of the bucket, its identifier in lowercase
/// and the digest of its version in force; and the tombstones of the items deleted, with the date of their deletion,
/// kept 180 days.
nonisolated struct VaultBucket: Codable, Equatable, Sendable {
    var deleted: [String: Date] = [:]
    var items: [String: String] = [:]

    /// How long a tombstone is kept, as a deletion on the server (`SYNC.md` § 4.9).
    static let tombstoneLifetime: TimeInterval = 180 * 24 * 3600

    /// Neither item nor tombstone: the root leaves it out.
    var isEmpty: Bool {
        deleted.isEmpty && items.isEmpty
    }

    /// The bucket of an item: the first hexadecimal character of its identifier, in lowercase.
    static func name(of itemID: UUID) -> String {
        String(itemID.uuidString.lowercased().prefix(1))
    }

    /// The sixteen buckets, `0` to `f`.
    static let names = (0 ..< 16).map { String($0, radix: 16) }
}

/// The root of the manifest, once opened (`VAULT.md` § 4.1).
nonisolated struct VaultRoot: Codable, Equatable, Sendable {
    /// For each bucket that isn't empty, the digest of its sealed `manifest`.
    var buckets: [String: String] = [:]
    /// Version vector: for each Mac that wrote the vault, its identifier in lowercase and the number of its writes.
    var clock: [String: Int] = [:]
    /// Date (sync clock) and Mac of this write, authenticated by the vault key.
    var modifiedAt: Date?
    var modifiedBy: UUID?

    /// Whether this root succeeds `other`: every entry of the clock of `other` is at most that of this one.
    func succeeds(_ other: VaultRoot) -> Bool {
        other.clock.allSatisfy { device, writes in (clock[device] ?? 0) >= writes }
    }

    /// Entry by entry, the larger of both clocks.
    func mergedClock(with other: VaultRoot) -> [String: Int] {
        clock.merging(other.clock, uniquingKeysWith: max)
    }

    /// The clock of a write by `device` on top of this root.
    func clock(ofWriteBy device: UUID) -> [String: Int] {
        var next = clock
        next[device.uuidString.lowercased(), default: 0] += 1
        return next
    }
}

/// Encryption of the manifest and of the files of the vault (`VAULT.md` § 4.1 and § 6). Pure type.
nonisolated enum VaultManifestCrypto {
    /// A file is cut into chunks of 16 MiB, the last one shorter.
    static let fileChunkBytes = 16 * 1024 * 1024

    static func bucketAAD(vaultID: UUID, bucket: String, keyVersion: Int) -> Data {
        Data("matcha.vault.bucket.v1|\(vaultID.uuidString.lowercased())|\(bucket)|\(keyVersion)".utf8)
    }

    static func rootAAD(vaultID: UUID, keyVersion: Int) -> Data {
        Data("matcha.vault.manifest.v1|\(vaultID.uuidString.lowercased())|\(keyVersion)".utf8)
    }

    /// `0x01 ‖ Seal(manifestKey, bucket padded to 256 bytes, aad)`.
    static func sealBucket(
        _ bucket: VaultBucket,
        named name: String,
        vaultID: UUID,
        keys: VaultCrypto.Keys,
        nonce: AES.GCM.Nonce? = nil,
    ) throws -> Data {
        let plain = try SyncCoding.encoder().encode(bucket)
        let aad = bucketAAD(vaultID: vaultID, bucket: name, keyVersion: VaultCrypto.keyVersion)
        return try VaultCrypto.versioned(SyncCrypto.seal(
            SyncCrypto.pad(plain, toMultipleOf: SyncCrypto.recordPadding),
            key: keys.manifest,
            aad: aad,
            nonce: nonce,
        ))
    }

    static func openBucket(_ sealed: Data, named name: String, vaultID: UUID, keys: VaultCrypto.Keys) throws -> VaultBucket {
        let aad = bucketAAD(vaultID: vaultID, bucket: name, keyVersion: VaultCrypto.keyVersion)
        let plain = try SyncCrypto.unpad(SyncCrypto.open(VaultCrypto.unversioned(sealed), key: keys.manifest, aad: aad))
        return try SyncCoding.decoder().decode(VaultBucket.self, from: plain)
    }

    /// `0x01 ‖ Seal(manifestKey, root padded to 256 bytes, aad)`.
    static func sealRoot(_ root: VaultRoot, vaultID: UUID, keys: VaultCrypto.Keys, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        let plain = try SyncCoding.encoder().encode(root)
        return try VaultCrypto.versioned(SyncCrypto.seal(
            SyncCrypto.pad(plain, toMultipleOf: SyncCrypto.recordPadding),
            key: keys.manifest,
            aad: rootAAD(vaultID: vaultID, keyVersion: VaultCrypto.keyVersion),
            nonce: nonce,
        ))
    }

    static func openRoot(_ sealed: Data, vaultID: UUID, keys: VaultCrypto.Keys) throws -> VaultRoot {
        let aad = rootAAD(vaultID: vaultID, keyVersion: VaultCrypto.keyVersion)
        let plain = try SyncCrypto.unpad(SyncCrypto.open(VaultCrypto.unversioned(sealed), key: keys.manifest, aad: aad))
        return try SyncCoding.decoder().decode(VaultRoot.self, from: plain)
    }

    /// Digest of a sealed bucket, as the root cites it: SHA-256 of its bytes, version and nonce included.
    static func bucketDigest(_ sealed: Data) -> String {
        SHA256.hash(data: sealed).hexString
    }

    // MARK: Files

    static func fileChunkAAD(fileID: UUID, index: Int, count: Int) -> Data {
        Data("matcha.vault.file.v1|\(fileID.uuidString.lowercased())|\(index)|\(count)".utf8)
    }

    /// Chunk `index` of `count` of a file: `0x01 ‖ Seal(fileKey, chunk padded to 64 KiB, aad)`; a chunk that is
    /// missing, moved or from another file doesn't open.
    static func encryptFileChunk(
        _ chunk: Data,
        fileID: UUID,
        index: Int,
        count: Int,
        key: SymmetricKey,
        nonce: AES.GCM.Nonce? = nil,
    ) throws -> Data {
        let padded = SyncCrypto.pad(chunk, toMultipleOf: SyncCrypto.blobPadding)
        let aad = fileChunkAAD(fileID: fileID, index: index, count: count)
        return try VaultCrypto.versioned(SyncCrypto.seal(padded, key: key, aad: aad, nonce: nonce))
    }

    static func decryptFileChunk(_ data: Data, fileID: UUID, index: Int, count: Int, key: SymmetricKey) throws -> Data {
        let aad = fileChunkAAD(fileID: fileID, index: index, count: count)
        return try SyncCrypto.unpad(SyncCrypto.open(VaultCrypto.unversioned(data), key: key, aad: aad))
    }

    /// Number of chunks of a file of `size` bytes: an empty file has one, empty.
    static func chunkCount(ofSize size: Int) -> Int {
        max(1, (size + fileChunkBytes - 1) / fileChunkBytes)
    }
}

/// Identifiers of the records of the manifest (`VAULT.md` § 4.1): derived from the account's `idKey`, the same on all
/// its Macs, unknown to the server.
nonisolated extension SyncIdentifiers {
    /// Record of the root of the manifest of `vaultID`.
    func vaultManifest(of vaultID: UUID) -> UUID {
        id(for: "vault-manifest:\(vaultID.uuidString.lowercased())")
    }

    /// Record of the bucket `name` (`0` to `f`) of the manifest of `vaultID`.
    func vaultBucket(_ name: String, of vaultID: UUID) -> UUID {
        id(for: "vault-bucket:\(vaultID.uuidString.lowercased())|\(name)")
    }
}
