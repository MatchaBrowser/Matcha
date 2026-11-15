import Foundation

/// What this Mac keeps of the vault of an account (`VAULT.md` § 5.2, § 7.4): its verified state, the changes made here
/// that haven't been applied by the server yet, and the batch in flight. Everything that matters is encrypted as it
/// arrived: the identifiers of the items, dates and the clock are the only things in clear text. Kept apart from
/// `SyncState`: the server can't erase it (`VAULT.md` § 5.5).
nonisolated struct VaultState: Codable, Equatable, Sendable {
    /// The vault it belongs to (`VaultCrypto.Keys.vaultID`); nil until the vault was opened once here.
    var vaultID: UUID?
    /// The sealed `manifest` of the root in force, and its version vector (in clear, to compare while locked).
    var root: Data?
    var clock: [String: Int] = [:]
    /// The sealed `manifest` of each bucket the root in force cites.
    var buckets: [String: Data] = [:]
    /// For each item the root in force cites, the version this Mac holds of it.
    var items: [UUID: VaultHeldItem] = [:]
    /// Changes made here, not yet applied by the server (`VAULT.md` § 5.1): sealed, they survive a lock or a restart.
    var edits: [UUID: VaultEdit] = [:]
    /// The batch sent and not yet answered: sent again as it is, with its key (`SYNC.md` § 4.6).
    var inFlight: VaultBatch?
    /// The server versions of the records of the vault this Mac knows: the `baseVersion` of its next write.
    var versions: [UUID: Int] = [:]
    /// Last repair of each record (`VAULT.md` § 5.3): at most one a day.
    var repairs: [UUID: Date] = [:]
    /// Packages of files no longer cited, and since when (`VAULT.md` § 6): deleted after 30 days.
    var obsoleteBlobs: [UUID: Date] = [:]
    /// Packages sent whose item may not be applied yet.
    var pendingBlobs: Set<UUID> = []
    /// What the last verification found, for the interface.
    var notice: VaultNotice?

    var isEmpty: Bool {
        root == nil && items.isEmpty && edits.isEmpty
    }

    /// The version to build on for `id`: the larger of the one kept here and the one the sync engine read.
    func baseVersion(of id: UUID, engine: Int?) -> Int? {
        switch (versions[id], engine) {
        case let (mine?, theirs?): max(mine, theirs)
        case let (mine, theirs): mine ?? theirs
        }
    }
}

/// The version of an item this Mac holds (`VAULT.md` § 5.2).
nonisolated struct VaultHeldItem: Codable, Equatable, Sendable {
    var sealed: VaultSealedItem
    /// Date and Mac of its overview, to tell a newer version from a rollback while comparing.
    var modifiedAt: Date?
    var modifiedBy: UUID?
    /// The root in force cites this version; false: the last verified version, shown while the cited one waits.
    var isCited = true
    /// In the trash: its overview's `trashedAt`.
    var trashedAt: Date?

    var digest: String {
        sealed.digest
    }
}

/// A change made on this Mac, not yet applied (`VAULT.md` § 5.1, § 5.4).
nonisolated struct VaultEdit: Codable, Equatable, Sendable {
    /// The new version; nil for a deletion for good (the item was in the trash).
    var sealed: VaultSealedItem?
    /// The verified version it started from, for a merge if another Mac changed it meanwhile; nil for a new item.
    var base: VaultSealedItem?
    var modifiedAt: Date?
    var modifiedBy: UUID?
    var trashedAt: Date?
    /// Packages of the files this version adds, already sent.
    var blobs: [UUID] = []
}

/// A batch of the vault, encrypted, with its key (`SYNC.md` § 4.6).
nonisolated struct VaultBatch: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Items, buckets and root, all or nothing.
        case atomic
        /// Items of a large write, before the atomic batch that cites them (`VAULT.md` § 5.1).
        case staging
        /// Records sent back as they are (`VAULT.md` § 5.3).
        case repair
    }

    var kind: Kind
    var key: UUID
    var changes: [SyncServerChange]
    /// The new root and buckets this batch writes, sealed, and the clock of the root: they become the state in force
    /// once applied.
    var root: Data?
    var clock: [String: Int] = [:]
    var buckets: [String: Data] = [:]
    /// The items it writes, as they become in the state.
    var items: [UUID: VaultHeldItem] = [:]
    /// The items it deletes for good.
    var deletions: Set<UUID> = []
}

/// What the vault tells the user after a verification (`VAULT.md` § 5.2, § 5.3).
nonisolated enum VaultNotice: String, Codable, Equatable, Sendable {
    /// A reconciliation or a repair: the server's vault was incomplete or older than this Mac's.
    case completedFromThisMac
    /// Items cited by the root that couldn't be verified yet.
    case itemsWaiting
    /// Records of the vault, but no readable root, and no state here: waiting for another Mac.
    case waitingForAnotherMac
}
