import Foundation
import Security

/// Sync keychain (`SYNC.md` § 3.8): account key, tokens and device identifier, as generic passwords of the
/// `com.matchabrowser.matcha.sync` service, in this Mac's login keychain (never synced by iCloud; in the sandbox,
/// reserved for Matcha). The data protection keychain would require a signed app identifier (provisioning profile,
/// `DECISIONS.md`). The master password, the master key and the recovery key never go there.
nonisolated struct SyncKeychain: Sendable {
    static let service = "com.matchabrowser.matcha.sync"

    /// Stored items.
    enum Item: String, CaseIterable, Sendable {
        case accountKey
        case accessToken
        case refreshToken
        case deviceID
    }

    /// Service of the items (a different one for tests).
    var service = Self.service

    func set(_ data: Data, for item: Item) throws {
        let query = baseQuery(for: item)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw SyncKeychainError(status: status)
        }
    }

    func data(for item: Item) -> Data? {
        var query = baseQuery(for: item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    /// Removes `items` (all by default: sign-out, revoked device).
    func remove(_ items: [Item] = Item.allCases) {
        for item in items {
            SecItemDelete(baseQuery(for: item) as CFDictionary)
        }
    }

    private func baseQuery(for item: Item) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
    }
}

nonisolated struct SyncKeychainError: Error, Equatable {
    let status: OSStatus
}
