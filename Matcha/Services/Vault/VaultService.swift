import CryptoKit
import Foundation
import Observation
import OSLog

/// The vault of the signed-in account (`VAULT.md`): its state on this Mac, locked or open, the list of its items, and
/// their writes through sync. Its keys exist only while it is open (`VaultSession`); on the disk, everything stays as
/// it arrived, encrypted.
@MainActor
@Observable
final class VaultService {
    enum Status: Equatable, Sendable {
        case unavailable(Unavailability)
        case locked
        case unlocked
    }

    enum Unavailability: Equatable, Sendable {
        /// Turned off on this Mac (Settings > Vault).
        case disabled
        /// Sync isn't signed in to an account.
        case signedOut
        /// The account was created before the vault: it has none.
        case noVault
        /// The server doesn't keep vaults (`features` without `vault`).
        case serverWithoutVault
        /// The envelope the server gave doesn't open (`VAULT.md` § 7.1).
        case envelopeUnreadable
    }

    private(set) var status = Status.unavailable(.signedOut)
    /// The vault is optional: turned off, Matcha doesn't offer it anywhere on this Mac (`setEnabled`).
    private(set) var isEnabled: Bool
    /// The items, their overviews opened; empty while locked. Set by the service's own extensions only.
    var items: [VaultListItem] = []
    /// What the last verification found (`VAULT.md` § 5.2, § 5.3).
    private(set) var notice: VaultNotice?
    /// Last write of the vault, from the root in force (`VAULT.md` § 4.1).
    private(set) var lastModifiedAt: Date?
    private(set) var lastModifiedBy: UUID?
    /// The last write failed for a reason the user must know (full account, item too large).
    private(set) var writeError: (any Error)?

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored var account: SyncVaultAccount?
    @ObservationIgnored var file = VaultStateFile(url: nil)
    @ObservationIgnored var state = VaultState()
    @ObservationIgnored var session: VaultSession?
    /// The sync state of the last complete read: what the server shows.
    @ObservationIgnored var serverState: SyncState?
    @ObservationIgnored var isWriting = false
    /// The write started by the last edit; tests wait for it.
    @ObservationIgnored var writeTask: Task<Void, Never>?
    @ObservationIgnored var lastActivity = Date.now
    @ObservationIgnored var failedAttempts = 0
    @ObservationIgnored var attemptsBlockedUntil: Date?
    @ObservationIgnored var lockTask: Task<Void, Never>?
    /// The public suffix list, read at the first filling (`VAULT.md` § 8.2).
    @ObservationIgnored var loadedMatcher: VaultURLMatcher?
    @ObservationIgnored var now: () -> Date = { .now }
    /// Asked before a write is sent while the Mac's clock is far ahead (`VAULT.md` § 5.6).
    @ObservationIgnored var clockLead: () -> TimeInterval = { 0 }
    /// Tells the interface to forget what it shows (the clipboard, opened files) when the vault locks.
    @ObservationIgnored var onLock: [@MainActor () -> Void] = []
    /// Tells the pages to stop or start talking to the filling when the vault is turned off or on.
    @ObservationIgnored var onEnabledChange: [@MainActor (Bool) -> Void] = []

    static let enabledKey = "vaultEnabled"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        refreshStatus()
    }

    var isUnlocked: Bool {
        session != nil
    }

    /// Notes a use of the vault or of the filling: the automatic lock counts from there (`VAULT.md` § 7.3).
    func noteActivity() {
        lastActivity = now()
    }

    // MARK: Status

    /// Whether Matcha offers the vault in its windows (its button, the filling): turned on, and sync signed in.
    var isOffered: Bool {
        isEnabled && status != .unavailable(.signedOut)
    }

    /// Turns the vault on or off on this Mac. Off, it's locked, and neither its window nor the filling is offered; its
    /// items stay in the account, and what this Mac verified stays kept for when it's turned on again.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        lock()
        refreshStatus()
        for observe in onEnabledChange {
            observe(enabled)
        }
        Logger.vault.info("Vault turned \(enabled ? "on" : "off", privacy: .public)")
    }

    /// What the vault can be, for the account signed in, while locked.
    func refreshStatus() {
        guard isEnabled else {
            status = .unavailable(.disabled)
            return
        }
        guard let account else {
            status = .unavailable(.signedOut)
            return
        }
        if session != nil {
            status = .unlocked
        } else if !account.serverHasVault, state.isEmpty {
            status = .unavailable(.serverWithoutVault)
        } else if (try? envelope()) == nil {
            status = .unavailable(.noVault)
        } else {
            status = .locked
        }
    }

    /// The envelope this Mac keeps for the account.
    func envelope() throws -> SyncVaultEnvelope? {
        guard let account,
              let data = try account.keychain.data(for: .vaultEnvelope, server: account.server, accountID: account.accountID)
        else {
            return nil
        }
        return try JSONDecoder().decode(SyncVaultEnvelope.self, from: data)
    }

    func saveState() {
        do {
            try file.save(state)
        } catch {
            Logger.vault.error("Vault state not saved: \(error.logSummary, privacy: .public)")
        }
    }

    // MARK: List

    /// The list from the state and the edits of this Mac, overviews opened (from a cache by digest).
    func rebuildItems() {
        guard let session else {
            items = []
            return
        }
        var list: [VaultListItem] = []
        for id in Set(state.items.keys).union(state.edits.keys) {
            let edit = state.edits[id]
            guard let sealed = edit.map(\.sealed) ?? state.items[id]?.sealed, let overview = session.overview(of: sealed, id: id) else {
                continue
            }
            list.append(VaultListItem(id: id, overview: overview, isWaiting: state.items[id]?.isCited == false, isPending: edit != nil))
        }
        items = list.sorted { $0.overview.title.localizedStandardCompare($1.overview.title) == .orderedAscending }
        notice = state.notice
        let root = state.root.flatMap { try? VaultManifestCrypto.openRoot($0, vaultID: session.keys.vaultID, keys: session.keys) }
        (lastModifiedAt, lastModifiedBy) = (root?.modifiedAt, root?.modifiedBy)
    }

    func setWriteError(_ error: (any Error)?) {
        writeError = error
    }
}

/// An item of the list: its overview, and how sure its version is.
nonisolated struct VaultListItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let overview: VaultOverview
    /// The root cites a version this Mac doesn't have yet (`VAULT.md` § 5.2): the one shown is the last verified.
    let isWaiting: Bool
    /// Changed here, not yet applied by the server.
    let isPending: Bool
}

/// The keys of the open vault, and the overviews already opened: forgotten when it locks.
@MainActor
final class VaultSession {
    /// Kept while open, to wrap it for Touch ID.
    let rootKey: SymmetricKey
    let keys: VaultCrypto.Keys
    let codec: VaultItemCodec
    private var overviews: [String: VaultOverview] = [:]

    init(vaultRootKey: SymmetricKey) {
        rootKey = vaultRootKey
        keys = VaultCrypto.Keys(vaultRootKey: vaultRootKey)
        codec = VaultItemCodec(keys: keys)
    }

    func overview(of sealed: VaultSealedItem, id: UUID) -> VaultOverview? {
        let digest = sealed.digest
        if let cached = overviews[digest] {
            return cached
        }
        guard let overview = try? codec.overview(of: sealed, id: id) else {
            return nil
        }
        overviews[digest] = overview
        return overview
    }
}
