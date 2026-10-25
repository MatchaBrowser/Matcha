import Foundation
import OSLog

/// Sync configuration of this Mac, not synced (`SYNC.md` § 1): the mode, the server and the account, and why this Mac
/// is signed out while sync stays on. Kept in `UserDefaults`, read leniently. Pure type.
nonisolated struct SyncConfiguration: Codable, Equatable, Sendable {
    static let defaultsKey = "syncConfiguration"

    enum Mode: String, Codable, Sendable {
        case off
        case privateServer
    }

    /// Why this Mac is signed out of its account (`SYNC.md` § 5).
    enum SignedOutReason: String, Codable, Sendable {
        /// Disconnected from another device, or after a password change elsewhere.
        case deviceRevoked
        /// Account deleted from another device.
        case accountDeleted
        /// Tokens unknown to the server: signing in again is needed.
        case sessionExpired
        /// This Mac is a copy of another one (Migration Assistant, Time Machine): signing in again draws its own identity.
        case copiedMac
    }

    var mode = Mode.off
    var server: SyncServerAddress?
    var accountID: UUID?
    var email: String?
    /// Description of the server, kept for launching sync without waiting for it (limits, events, packages).
    var serverInfo: SyncServerInfo?
    var signedOutReason: SignedOutReason?
    /// Date of the account's avatar kept in cache: downloaded again only when the server announces another one.
    var avatarUpdatedAt: Date?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = container.lenient(Mode.self, forKey: .mode) ?? .off
        server = container.lenient(SyncServerAddress.self, forKey: .server)
        accountID = container.lenient(UUID.self, forKey: .accountID)
        email = container.lenient(String.self, forKey: .email)
        serverInfo = container.lenient(SyncServerInfo.self, forKey: .serverInfo)
        signedOutReason = container.lenient(SignedOutReason.self, forKey: .signedOutReason)
        avatarUpdatedAt = container.lenient(Date.self, forKey: .avatarUpdatedAt)
    }

    static func load(from defaults: UserDefaults) -> SyncConfiguration {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return SyncConfiguration()
        }
        do {
            return try SyncCoding.decoder().decode(SyncConfiguration.self, from: data)
        } catch {
            Logger.sync.error("Sync configuration unreadable: \(error.logSummary, privacy: .public)")
            return SyncConfiguration()
        }
    }

    /// A configuration that can't be encoded keeps the previous one, rather than erasing it (review TR4).
    func save(to defaults: UserDefaults) {
        do {
            try defaults.set(SyncCoding.encoder().encode(self), forKey: Self.defaultsKey)
        } catch {
            Logger.sync.error("Sync configuration not saved: \(error.logSummary, privacy: .public)")
        }
    }

    /// Identifier typed by the user, as client and server compare it: without spaces around, in lowercase
    /// (`SYNC.md` § 4.1).
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// What the user must keep to recover the account without the master password (`SYNC.md` § 3.3): the server's
/// address, the identifier and the recovery key. Shown once, saved as a PDF or printed before continuing.
nonisolated struct SyncRecoveryKit: Equatable, Sendable {
    let server: SyncServerAddress
    let email: String
    let recoveryKey: String
}
