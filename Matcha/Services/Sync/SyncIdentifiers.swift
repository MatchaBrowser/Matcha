import CryptoKit
import Foundation

/// Identifiers derived from a key (`SYNC.md` § 2.2): the same on all the Macs of an account, for what has no object of
/// its own or what two Macs can each create on their side. HMAC-SHA256 of the name with the account's `idKey`, shaped
/// as a version 8 UUID: without the key, a server can't recompute them from a site, an origin or an extension. Pure
/// type.
nonisolated struct SyncIdentifiers: Sendable {
    let idKey: SymmetricKey

    init(idKey: SymmetricKey) {
        self.idKey = idKey
    }

    init(accountKey: SymmetricKey) {
        idKey = SyncAccountKeys.idKey(accountKey: accountKey)
    }

    /// First 16 bytes of HMAC-SHA256(idKey, name in UTF-8), with the version (8) and variant bits of RFC 9562 § 5.8.
    func id(for name: String) -> UUID {
        var bytes = Array(HMAC<SHA256>.authenticationCode(for: Data(name.utf8), using: idKey).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
        ))
    }

    func setting(_ key: String) -> UUID {
        id(for: "setting:\(key)")
    }

    func siteZoom(_ site: String) -> UUID {
        id(for: "site-zoom:\(site)")
    }

    func sitePermission(profileID: UUID?, origin: String, kind: String) -> UUID {
        id(for: Self.sitePermissionName(profileID: profileID, origin: origin, kind: kind))
    }

    /// Extension installed from a file, by its identifier in Matcha.
    func packageExtension(_ identifier: String) -> UUID {
        id(for: "extension:\(identifier)")
    }

    /// An app's Safari extension, by the exact bundle identifier of its `.appex`: two of them can share an identifier
    /// in Matcha (`SYNC.md` § 2.5).
    func appExtension(bundleIdentifier: String) -> UUID {
        id(for: "extension-app:\(bundleIdentifier)")
    }

    func webExtension(_ fields: SyncExtensionFields) -> UUID {
        id(for: Self.extensionName(fields))
    }

    /// Today tabs of the Mac `deviceID`, read-only for the others (`SYNC.md` § 2.4).
    func deviceTabs(_ deviceID: UUID) -> UUID {
        id(for: "device-tabs:\(deviceID.uuidString.lowercased())")
    }

    /// Profile and Space recreated by sync when received deletions leave none (`SYNC.md` § 2.3, invariants).
    var defaultProfile: UUID {
        id(for: "default-profile")
    }

    var defaultSpace: UUID {
        id(for: "default-space")
    }

    /// Identifier that a record with `fields` must have; nil for a type whose identifier is that of its model
    /// (profile, Space, folder, tab). Checked on reception (`SYNC.md` § 2.2).
    func expectedID(of fields: SyncFields) -> UUID? {
        switch fields {
        case let .setting(fields): setting(fields.key)
        case let .siteZoom(fields): siteZoom(fields.site)
        case let .sitePermission(fields): sitePermission(profileID: fields.profileId, origin: fields.origin, kind: fields.kind)
        case let .webExtension(fields): webExtension(fields)
        case let .deviceTabs(fields): deviceTabs(fields.deviceId)
        case .profile, .space, .folder, .tab: nil
        }
    }

    static func sitePermissionName(profileID: UUID?, origin: String, kind: String) -> String {
        "site-permission:\(profileID?.uuidString.lowercased() ?? "")|\(origin)|\(kind)"
    }

    static func extensionName(_ fields: SyncExtensionFields) -> String {
        if fields.source.kind == .appExtension, let bundleIdentifier = fields.source.bundleIdentifier {
            return "extension-app:\(bundleIdentifier)"
        }
        return "extension:\(fields.identifier)"
    }
}
