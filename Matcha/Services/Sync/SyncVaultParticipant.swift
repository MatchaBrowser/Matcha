import CryptoKit
import Foundation

/// The account the vault works with, as sync starts it (`VAULT.md` § 5): the client to push with, the keys of the outer
/// layer, this Mac's identity, and where the vault keeps its state.
@MainActor
struct SyncVaultAccount {
    let server: SyncServerAddress
    let accountID: UUID
    /// The client of the account, for the packages of files; nil in tests without a server.
    let client: SyncAPIClient?
    let identifiers: SyncIdentifiers
    /// Key of the outer layer of every record (`SYNC.md` § 3.5).
    let dataKey: SymmetricKey
    let deviceID: UUID
    let keychain: SyncKeychain
    /// File of the vault's state, next to the sync state; nil: kept in memory (tests).
    let stateURL: URL?
    /// The server keeps the vault's envelopes and takes atomic pushes (`SYNC.md` § 4.2).
    let serverHasVault: Bool
    /// Asks for a sync cycle soon: to read after a conflict, or to send what the vault wrote.
    let requestCycle: @MainActor () -> Void
    /// Sends a push body under its `Idempotency-Key`: the client's, or a fake server in tests.
    let push: @MainActor (_ body: Data, _ key: UUID) async throws -> SyncPushResponse
    /// Largest encrypted package the server keeps (`SYNC.md` § 4.2): a chunk of a file of the vault is under it.
    var maxBlobBytes = SyncServerInfo(api: 1).maximumBlobBytes
}

/// The vault, as sync sees it: started and stopped with the account, told after each cycle.
@MainActor
protocol SyncVaultParticipant: AnyObject {
    func syncDidActivate(_ account: SyncVaultAccount)
    /// Sync stopped: the vault locks. `forgetting`: the user signed out of this Mac or deleted the account from it, the
    /// vault's state is deleted; otherwise (revoked, deleted elsewhere, expired) it stays (`VAULT.md` § 5.5).
    func syncDidDeactivate(forgetting: Bool)
    /// After a cycle that read everything: the vault verifies and writes (`VAULT.md` § 5.2).
    func syncCycleDidFinish(state: SyncState) async
}
