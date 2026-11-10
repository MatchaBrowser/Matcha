import CryptoKit
import Foundation

/// Encryption of the vault (`VAULT.md` § 2 and § 3): the root key and its envelopes, the keys of the personal vault,
/// the two inner parts of an item and its digest. Built on `SyncCrypto` (AES-256-GCM, HKDF-SHA256, ISO/IEC 7816-4
/// padding). Pure type.
nonisolated enum VaultCrypto {
    /// Associated data of both envelopes of the vault root key: not that of the account key, so that a server that
    /// swaps them is seen.
    static let rootKeyAAD = Data("matcha.vault-root-key.v1".utf8)
    /// The details are padded to at least 1 KiB, then with Padmé.
    static let detailsFloor = 1024
    /// Version of the personal vault's key: 1 in v1 (`VAULT.md` § 3.1).
    static let keyVersion = 1

    /// Keys of the personal vault, derived from its root key (`VAULT.md` § 2.1, § 2.3).
    struct Keys: Sendable {
        let vault: SymmetricKey
        /// Wraps the key of each item.
        let itemWrap: SymmetricKey
        /// Encrypts and authenticates the manifest.
        let manifest: SymmetricKey

        /// Identifier of the vault: the first 16 bytes of HKDF(vaultKey, "matcha.vault.id.v1"), shaped as a version 8
        /// UUID (`VAULT.md` § 2.3). It doesn't depend on the account key.
        let vaultID: UUID

        init(vaultRootKey: SymmetricKey) {
            let vault = SyncCrypto.subkey(of: vaultRootKey, info: "matcha.vault.personal.v1")
            self.vault = vault
            itemWrap = SyncCrypto.subkey(of: vault, info: "matcha.vault.item-wrap.v1")
            manifest = SyncCrypto.subkey(of: vault, info: "matcha.vault.manifest.v1")
            vaultID = SyncCrypto.subkey(of: vault, info: "matcha.vault.id.v1").withUnsafeBytes { VaultCrypto.uuid8(Array($0)) }
        }
    }

    /// The first 16 bytes of `bytes`, with the version (8) and variant bits of RFC 9562 § 5.8.
    static func uuid8(_ bytes: [UInt8]) -> UUID {
        var raw = Array(bytes.prefix(16))
        raw[6] = (raw[6] & 0x0F) | 0x80
        raw[8] = (raw[8] & 0x3F) | 0x80
        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15],
        ))
    }

    // MARK: Root key

    /// Envelope of the vault root key with `wrapKey` or `recoveryWrapKey`; `nonce` only for the vectors.
    static func wrapRootKey(_ vaultRootKey: SymmetricKey, with wrapKey: SymmetricKey, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        try SyncCrypto.seal(vaultRootKey.withUnsafeBytes { Data($0) }, key: wrapKey, aad: rootKeyAAD, nonce: nonce)
    }

    /// The vault root key; a failure means a wrong key (a wrong password) or a tampered envelope.
    static func unwrapRootKey(_ wrapped: Data, with wrapKey: SymmetricKey) throws -> SymmetricKey {
        let bytes = try SyncCrypto.open(wrapped, key: wrapKey, aad: rootKeyAAD)
        guard bytes.count == 32 else {
            throw SyncCryptoError.unreadable
        }
        return SymmetricKey(data: bytes)
    }

    // MARK: Padding

    /// Padmé (Nikitin et al., 2019): `length` rounded up to a multiple of 2^(⌊log₂ L⌋ − ⌊log₂ ⌊log₂ L⌋⌋ − 1); at most 12 %
    /// more, and only O(log log n) bits of the size leak.
    static func padme(_ length: Int) -> Int {
        guard length >= 2 else {
            return length
        }
        let exponent = Int.bitWidth - 1 - length.leadingZeroBitCount
        let bits = Int.bitWidth - exponent.leadingZeroBitCount
        let mask = (1 << (exponent - bits)) - 1
        return (length + mask) & ~mask
    }

    /// The details padded to Padmé(max(n + 1, 1 KiB)) bytes: `0x80`, then `0x00` (`VAULT.md` § 3.2).
    static func padDetails(_ data: Data) -> Data {
        var padded = data
        padded.append(0x80)
        let target = padme(max(data.count + 1, detailsFloor))
        padded.append(Data(count: target - padded.count))
        return padded
    }

    // MARK: Items

    /// The three sealed parts of an item, as its record carries them (`VAULT.md` § 3.1).
    enum Part: String, Sendable {
        case itemKey = "item-key"
        case overview
        case details
    }

    /// `matcha.vault.<part>.v1|<vaultId>|<itemId>|<keyVersion>`, identifiers in lowercase.
    static func aad(_ part: Part, vaultID: UUID, itemID: UUID, keyVersion: Int) -> Data {
        Data("matcha.vault.\(part.rawValue).v1|\(vaultID.uuidString.lowercased())|\(itemID.uuidString.lowercased())|\(keyVersion)".utf8)
    }

    /// Where an item is: its vault, its identifier and the version of the vault key.
    struct Address: Equatable, Sendable {
        let vaultID: UUID
        let itemID: UUID
        var keyVersion = VaultCrypto.keyVersion

        func aad(_ part: Part) -> Data {
            VaultCrypto.aad(part, vaultID: vaultID, itemID: itemID, keyVersion: keyVersion)
        }
    }

    /// Nonces of the three parts: random, except for the vectors.
    struct Nonces {
        var itemKey: AES.GCM.Nonce?
        var overview: AES.GCM.Nonce?
        var details: AES.GCM.Nonce?
    }

    /// Seals an item: its key under `itemWrapKey`, its overview (padded to 256 bytes) and details (Padmé) under its key.
    static func sealItem(
        overview: Data,
        details: Data,
        itemKey: SymmetricKey,
        at address: Address,
        keys: Keys,
        nonces: Nonces = Nonces(),
    ) throws -> VaultSealedItem {
        let rawKey = itemKey.withUnsafeBytes { Data($0) }
        return try VaultSealedItem(
            itemKey: versioned(SyncCrypto.seal(rawKey, key: keys.itemWrap, aad: address.aad(.itemKey), nonce: nonces.itemKey)),
            overview: sealOverview(overview, itemKey: itemKey, at: address, nonce: nonces.overview),
            details: sealDetails(details, itemKey: itemKey, at: address, nonce: nonces.details),
        )
    }

    static func sealOverview(_ overview: Data, itemKey: SymmetricKey, at address: Address, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        let padded = SyncCrypto.pad(overview, toMultipleOf: SyncCrypto.recordPadding)
        return try versioned(SyncCrypto.seal(padded, key: itemKey, aad: address.aad(.overview), nonce: nonce))
    }

    static func sealDetails(_ details: Data, itemKey: SymmetricKey, at address: Address, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        try versioned(SyncCrypto.seal(padDetails(details), key: itemKey, aad: address.aad(.details), nonce: nonce))
    }

    /// The key of an item.
    static func openItemKey(of item: VaultSealedItem, at address: Address, keys: Keys) throws -> SymmetricKey {
        let bytes = try SyncCrypto.open(unversioned(item.itemKey), key: keys.itemWrap, aad: address.aad(.itemKey))
        guard bytes.count == 32 else {
            throw SyncCryptoError.unreadable
        }
        return SymmetricKey(data: bytes)
    }

    static func openOverview(of item: VaultSealedItem, itemKey: SymmetricKey, at address: Address) throws -> Data {
        try SyncCrypto.unpad(SyncCrypto.open(unversioned(item.overview), key: itemKey, aad: address.aad(.overview)))
    }

    static func openDetails(of item: VaultSealedItem, itemKey: SymmetricKey, at address: Address) throws -> Data {
        try SyncCrypto.unpad(SyncCrypto.open(unversioned(item.details), key: itemKey, aad: address.aad(.details)))
    }

    // MARK: Format byte

    static func versioned(_ sealed: Data) -> Data {
        Data([SyncCrypto.formatVersion]) + sealed
    }

    /// What follows the version byte, if it is known.
    static func unversioned(_ data: Data) throws -> Data {
        guard data.first == SyncCrypto.formatVersion else {
            throw SyncCryptoError.unreadable
        }
        return data.dropFirst()
    }
}

/// The three sealed parts of an item, with the version byte (`VAULT.md` § 3.1), as they arrive and as they stay on the
/// disk: the local cache of the vault is encrypted.
nonisolated struct VaultSealedItem: Codable, Equatable, Hashable, Sendable {
    var itemKey: Data
    var overview: Data
    var details: Data

    /// Digest of this version of the item (`VAULT.md` § 3.3): SHA-256 of the label and of the three parts, each
    /// preceded by its length on 4 bytes, big-endian; 64 lowercase hexadecimal characters.
    var digest: String {
        var hash = SHA256()
        hash.update(data: Data("matcha.vault.item.v1".utf8))
        for part in [itemKey, overview, details] {
            withUnsafeBytes(of: UInt32(part.count).bigEndian) { hash.update(bufferPointer: $0) }
            hash.update(data: part)
        }
        return hash.finalize().hexString
    }
}

nonisolated extension Digest {
    /// Lowercase hexadecimal.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
