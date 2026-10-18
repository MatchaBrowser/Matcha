import Foundation

/// Champs d'une extension installée (`SYNC.md` § 2.5) : d'où elle vient, ses réglages et les décisions sur ses
/// permissions (nom ou motif → date d'expiration, nil sans expiration).
nonisolated struct SyncExtensionFields: Codable, Equatable, Sendable {
    var identifier: String
    var name: String
    var version: String?
    var source: SyncExtensionSource
    var isEnabled: Bool
    var allowsPrivateWindows: Bool
    var showsButton: Bool
    var grantedPermissions: [String: Date?]
    var deniedPermissions: [String: Date?]
    var grantedMatchPatterns: [String: Date?]
    var deniedMatchPatterns: [String: Date?]
}

/// Origine d'une extension : l'extension Safari d'une app (chargée depuis l'app sur chaque Mac), ou un paquet installé
/// depuis un fichier, envoyé chiffré à part (`blobId`, avec sa clé `blobKey` en base 64).
nonisolated struct SyncExtensionSource: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case appExtension
        case package
    }

    var kind: Kind
    var bundleIdentifier: String?
    var appBundleIdentifier: String?
    var appName: String?
    var blobId: UUID?
    var blobKey: String?
    var sha256: String?
    var size: Int?
    var fileName: String?

    static func appExtension(bundleIdentifier: String, appBundleIdentifier: String?, appName: String?) -> SyncExtensionSource {
        SyncExtensionSource(
            kind: .appExtension,
            bundleIdentifier: bundleIdentifier,
            appBundleIdentifier: appBundleIdentifier,
            appName: appName,
        )
    }

    static func package(blobID: UUID?, blobKey: String?, sha256: String?, size: Int?, fileName: String?) -> SyncExtensionSource {
        SyncExtensionSource(kind: .package, blobId: blobID, blobKey: blobKey, sha256: sha256, size: size, fileName: fileName)
    }
}
