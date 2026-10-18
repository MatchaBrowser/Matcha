import CryptoKit
import Foundation

/// Identifiants tirés d'une clé (tâche 7.4, `SYNC.md` § 2.2) : UUID version 5 (SHA-1, RFC 9562), les mêmes sur tous les
/// Mac, pour ce qui n'a pas d'objet propre ou que deux Mac peuvent créer chacun de leur côté. Type pur.
nonisolated enum SyncIdentifier {
    /// Espace de noms de Matcha : 393070D0-1478-44F6-82BF-07476B17D5F5.
    static let namespace = UUID(uuid: (
        0x39, 0x30, 0x70, 0xD0, 0x14, 0x78, 0x44, 0xF6, 0x82, 0xBF, 0x07, 0x47, 0x6B, 0x17, 0xD5, 0xF5,
    ))

    static func setting(_ key: String) -> UUID {
        derived(from: "setting:\(key)")
    }

    static func siteZoom(_ site: String) -> UUID {
        derived(from: "site-zoom:\(site)")
    }

    static func sitePermission(profileID: UUID?, origin: String, kind: String) -> UUID {
        let profile = profileID?.uuidString.lowercased() ?? ""
        return derived(from: "site-permission:\(profile)|\(origin)|\(kind)")
    }

    static func webExtension(_ identifier: String) -> UUID {
        derived(from: "extension:\(identifier)")
    }

    /// UUID version 5 de `name` (UTF-8) dans `namespace`.
    static func derived(from name: String, in namespace: UUID = namespace) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
        ))
    }
}
