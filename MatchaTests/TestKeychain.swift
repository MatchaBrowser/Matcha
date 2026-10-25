import Foundation
@testable import Matcha
import Security

/// Keychain services of a test, emptied with it (review TS3): a test never touches Matcha's own items
/// (`SyncKeychain.service`), and leaves none of its own behind. Held by the test (a property of its type).
final class TestKeychain: @unchecked Sendable {
    private var services: [String] = []

    /// A keychain of a service of its own, empty.
    func make() -> SyncKeychain {
        let service = "com.matchabrowser.matcha.sync.tests.\(UUID().uuidString)"
        services.append(service)
        return SyncKeychain(service: service)
    }

    deinit {
        for service in services {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            // One item at a time on some keychains: until none is left.
            while SecItemDelete(query as CFDictionary) == errSecSuccess {}
        }
    }
}
