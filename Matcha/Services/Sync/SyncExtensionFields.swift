import Foundation

/// Fields of an installed extension (`SYNC.md` § 2.5): where it comes from, its settings and the decisions on its
/// permissions (name or pattern → expiration date, nil without expiration).
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

    init(
        identifier: String,
        name: String,
        version: String?,
        source: SyncExtensionSource,
        isEnabled: Bool,
        allowsPrivateWindows: Bool,
        showsButton: Bool,
        grantedPermissions: [String: Date?],
        deniedPermissions: [String: Date?],
        grantedMatchPatterns: [String: Date?],
        deniedMatchPatterns: [String: Date?],
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.source = source
        self.isEnabled = isEnabled
        self.allowsPrivateWindows = allowsPrivateWindows
        self.showsButton = showsButton
        self.grantedPermissions = grantedPermissions
        self.deniedPermissions = deniedPermissions
        self.grantedMatchPatterns = grantedMatchPatterns
        self.deniedMatchPatterns = deniedMatchPatterns
    }

    /// Lenient reading (`SYNC.md` § 2.9): without its identifier or a readable source, the record is ignored; the
    /// other fields take their default value, and a permission with an unreadable expiration date is left out.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.required(String.self, forKey: .identifier)
        source = try container.required(SyncExtensionSource.self, forKey: .source)
        name = container.lenient(String.self, forKey: .name) ?? ""
        version = container.lenient(String.self, forKey: .version)
        isEnabled = container.lenient(Bool.self, forKey: .isEnabled) ?? false
        allowsPrivateWindows = container.lenient(Bool.self, forKey: .allowsPrivateWindows) ?? false
        showsButton = container.lenient(Bool.self, forKey: .showsButton) ?? true
        grantedPermissions = Self.expirations(in: container, forKey: .grantedPermissions)
        deniedPermissions = Self.expirations(in: container, forKey: .deniedPermissions)
        grantedMatchPatterns = Self.expirations(in: container, forKey: .grantedMatchPatterns)
        deniedMatchPatterns = Self.expirations(in: container, forKey: .deniedMatchPatterns)
    }

    /// Name or pattern → expiration date, nil without expiration; an unreadable date leaves its entry out.
    private static func expirations<Key: CodingKey>(in container: KeyedDecodingContainer<Key>, forKey key: Key) -> [String: Date?] {
        let values = container.lenient([String: SyncJSON].self, forKey: key) ?? [:]
        var result: [String: Date?] = [:]
        for (name, value) in values {
            switch value {
            case .null:
                result[name] = .some(nil)
            case let .string(text):
                if let date = SyncCoding.date(from: text) {
                    result[name] = date
                }
            default:
                continue
            }
        }
        return result
    }
}

/// Origin of an extension: an app's Safari extension (loaded from the app on each Mac), or a package installed from a
/// file, uploaded encrypted separately (`blobId`, with its key `blobKey` in base 64).
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

    init(
        kind: Kind,
        bundleIdentifier: String? = nil,
        appBundleIdentifier: String? = nil,
        appName: String? = nil,
        blobId: UUID? = nil,
        blobKey: String? = nil,
        sha256: String? = nil,
        size: Int? = nil,
        fileName: String? = nil,
    ) {
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.blobId = blobId
        self.blobKey = blobKey
        self.sha256 = sha256
        self.size = size
        self.fileName = fileName
    }

    /// Lenient reading (`SYNC.md` § 2.9): an app's extension needs its bundle identifiers; a package that has been
    /// uploaded needs its identifier, its 32-byte key, its digest and its size. A package not uploaded (none of
    /// them) travels as such: the other Macs show the extension “to reinstall”.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.required(Kind.self, forKey: .kind)
        appName = container.lenient(String.self, forKey: .appName)
        fileName = container.lenient(String.self, forKey: .fileName)
        switch kind {
        case .appExtension:
            bundleIdentifier = try container.required(String.self, forKey: .bundleIdentifier)
            appBundleIdentifier = try container.required(String.self, forKey: .appBundleIdentifier)
        case .package:
            blobId = container.lenient(UUID.self, forKey: .blobId)
            blobKey = container.lenient(String.self, forKey: .blobKey)
            sha256 = container.lenient(String.self, forKey: .sha256)
            size = container.lenient(Int.self, forKey: .size)
            let parts: [Bool] = [blobId != nil, blobKey != nil, sha256 != nil, size != nil]
            guard parts.allSatisfy(\.self) || !parts.contains(true) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Incomplete package"))
            }
            if let blobKey, Data(base64Encoded: blobKey)?.count != 32 {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid package key"))
            }
            if let sha256, sha256.count != 64 || !sha256.allSatisfy(\.isHexDigit) {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid digest"))
            }
        }
    }
}
