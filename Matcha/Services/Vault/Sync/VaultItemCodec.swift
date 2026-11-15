import CryptoKit
import Foundation

/// Opens and seals the content of an item with the keys of the open vault. Pure type.
nonisolated struct VaultItemCodec: Sendable {
    let keys: VaultCrypto.Keys

    /// An item opened: its key and its content.
    struct Opened: Sendable {
        let itemKey: SymmetricKey
        let content: VaultItemContent
    }

    func address(of id: UUID) -> VaultCrypto.Address {
        VaultCrypto.Address(vaultID: keys.vaultID, itemID: id)
    }

    func open(_ item: VaultSealedItem, id: UUID) throws -> Opened {
        let address = address(of: id)
        let itemKey = try VaultCrypto.openItemKey(of: item, at: address, keys: keys)
        let content = try VaultItemContent(
            overview: VaultCrypto.openOverview(of: item, itemKey: itemKey, at: address),
            details: VaultCrypto.openDetails(of: item, itemKey: itemKey, at: address),
        )
        return Opened(itemKey: itemKey, content: content)
    }

    /// Only the overview: what the list reads.
    func overview(of item: VaultSealedItem, id: UUID) throws -> VaultOverview {
        let address = address(of: id)
        let itemKey = try VaultCrypto.openItemKey(of: item, at: address, keys: keys)
        let data = try VaultCrypto.openOverview(of: item, itemKey: itemKey, at: address)
        return try VaultOverview(json: SyncCoding.decoder().decode(SyncJSON.self, from: data))
    }

    /// A new version: new nonces, the item's key kept for its whole life (a new one for a new item). Refuses parts over
    /// their limits (`VAULT.md` § 3.2).
    func seal(_ content: VaultItemContent, id: UUID, itemKey: SymmetricKey?) throws -> VaultSealedItem {
        let overview = try content.encodedOverview()
        let details = try content.encodedDetails()
        guard overview.count <= 4 * 1024, details.count <= VaultDetails.maximumBytes else {
            throw VaultError.itemTooLarge
        }
        return try VaultCrypto.sealItem(
            overview: overview,
            details: details,
            itemKey: itemKey ?? SymmetricKey(size: .bits256),
            at: address(of: id),
            keys: keys,
        )
    }

    /// The held form of a version.
    static func held(_ sealed: VaultSealedItem, content: VaultItemContent) -> VaultHeldItem {
        VaultHeldItem(
            sealed: sealed,
            modifiedAt: content.overview.modifiedAt,
            modifiedBy: content.overview.modifiedBy,
            trashedAt: content.overview.trashedAt,
        )
    }
}

/// Errors of the vault, for the interface.
nonisolated enum VaultError: Error, Equatable, Sendable {
    /// The vault is locked.
    case locked
    /// The overview or the details are over their limits.
    case itemTooLarge
    /// More than 10 000 items and tombstones (`VAULT.md` § 4.1).
    case vaultFull
    /// The password doesn't open the vault.
    case wrongPassword
    /// The account has no vault, or the server keeps none.
    case unavailable
    /// The item comes from a newer version of Matcha: read-only.
    case readOnly
    /// Too many wrong passwords: wait.
    case tooManyAttempts(until: Date)
}
