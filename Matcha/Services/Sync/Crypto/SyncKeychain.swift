import Foundation
import OSLog
import Security

/// Sync keychain (`SYNC.md` § 3.8): generic passwords of the `com.matchabrowser.matcha.sync` service, in this Mac's
/// login keychain, marked not synchronizable (`kSecAttrSynchronizable` false: never in iCloud Keychain); the sandbox
/// keeps them to Matcha. The account key and the tokens are stored by server and by account
/// (“<server>|<account>|<item>”): changing server or account mixes nothing. This Mac's identifier and machine mark are
/// for the whole Mac (“device”). A keychain error (locked, access refused) is an error, never an absence. The master
/// password, the master key and the recovery key never go there.
nonisolated struct SyncKeychain: Sendable {
    static let service = "com.matchabrowser.matcha.sync"

    /// Items of an account.
    enum Item: String, CaseIterable, Sendable {
        case accountKey
        case accessToken
        case refreshToken
    }

    /// Service of the items (a different one for tests).
    var service = Self.service

    // MARK: Account items

    func set(_ data: Data, for item: Item, server: SyncServerAddress, accountID: UUID) throws {
        try set(data, account: Self.name(of: item, server: server, accountID: accountID))
    }

    func data(for item: Item, server: SyncServerAddress, accountID: UUID) throws -> Data? {
        try data(account: Self.name(of: item, server: server, accountID: accountID))
    }

    /// Removes the account's items (sign-out, revoked device, deleted account).
    func removeAccount(server: SyncServerAddress, accountID: UUID, items: [Item] = Item.allCases) {
        for item in items {
            remove(account: Self.name(of: item, server: server, accountID: accountID))
        }
    }

    static func name(of item: Item, server: SyncServerAddress, accountID: UUID) -> String {
        "\(server.normalized)|\(accountID.uuidString.lowercased())|\(item.rawValue)"
    }

    // MARK: This Mac

    /// This Mac's sync identity: its device identifier, and the mark of the machine that drew it.
    struct Device: Codable, Equatable, Sendable {
        var id: UUID
        var machineMark: String?
    }

    /// This Mac's identity; nil if it has none yet. An item that can't be decoded is logged, then replaced by a new
    /// identity: this Mac becomes another device of the account rather than staying unable to sync (review TR4).
    func device() throws -> Device? {
        guard let data = try data(account: "device") else {
            return nil
        }
        do {
            return try JSONDecoder().decode(Device.self, from: data)
        } catch {
            Logger.sync.error("Device identity undecodable, replaced: \(error.logSummary, privacy: .public)")
            return nil
        }
    }

    func setDevice(_ device: Device) throws {
        try set(JSONEncoder().encode(device), account: "device")
    }

    /// Forgets this Mac's identity (tests).
    func removeDevice() {
        remove(account: "device")
    }

    // MARK: Keychain

    private func set(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrSynchronizable as String] = false
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw SyncClientError.keychain(status)
        }
    }

    private func data(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw SyncClientError.keychain(status)
        }
    }

    /// Deletes an item; a failure is logged (status only): the item stays in the keychain (review TR4).
    private func remove(account: String) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            Logger.sync.error("Keychain item not deleted: \(status, privacy: .public)")
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
