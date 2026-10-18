import Foundation
import Security

/// Trousseau de la synchro (`SYNC.md` § 3.8) : clé de compte, jetons et identifiant de l'appareil, en mots de passe
/// génériques du service `com.matchabrowser.matcha.sync`, dans le trousseau de session de ce Mac (jamais synchronisé par
/// iCloud ; dans le bac à sable, réservé à Matcha). Le trousseau protégé par l'appareil demanderait un identifiant
/// d'app signé (profil de provisionnement, `DECISIONS.md`). Le mot de passe maître, la clé maître et la clé de secours
/// n'y vont jamais.
nonisolated struct SyncKeychain: Sendable {
    static let service = "com.matchabrowser.matcha.sync"

    /// Éléments retenus.
    enum Item: String, CaseIterable, Sendable {
        case accountKey
        case accessToken
        case refreshToken
        case deviceID
    }

    /// Service des éléments (un autre pour les tests).
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

    /// Retire `items` (tous par défaut : déconnexion, appareil révoqué).
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
