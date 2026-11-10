import Foundation

/// Category of an item (`VAULT.md` § 9.3). An unknown category is kept as it is, and the item is read-only.
nonisolated enum VaultCategory: Equatable, Hashable, Sendable {
    case login
    case note
    case card
    case identity
    case document
    case sshKey
    case file
    case custom
    /// A category of a newer version: shown with its title, read-only.
    case unknown(String)

    static let known: [VaultCategory] = [.login, .note, .card, .identity, .document, .sshKey, .file, .custom]

    init(rawValue: String) {
        self = Self.known.first { $0.rawValue == rawValue } ?? .unknown(rawValue)
    }

    var rawValue: String {
        switch self {
        case .login: "login"
        case .note: "note"
        case .card: "card"
        case .identity: "identity"
        case .document: "document"
        case .sshKey: "sshKey"
        case .file: "file"
        case .custom: "custom"
        case let .unknown(name): name
        }
    }

    var isKnown: Bool {
        if case .unknown = self {
            return false
        }
        return true
    }
}

/// Credential types of CXF used by the categories of the v1 (`VAULT.md` § 9.3), and the secret keys of each.
nonisolated enum VaultCredentialType {
    static let basicAuth = "basic-auth"
    static let totp = "totp"
    static let creditCard = "credit-card"
    static let personName = "person-name"
    static let address = "address"
    static let passport = "passport"
    static let driversLicense = "drivers-license"
    static let identityDocument = "identity-document"
    static let sshKey = "ssh-key"

    static let known: Set<String> = [basicAuth, totp, creditCard, personName, address, passport, driversLicense, identityDocument, sshKey]

    /// The keys whose value is a secret, by credential type: masked, kept in the history when they change, and merged
    /// without loss (`VAULT.md` § 5.4, § 9.5).
    static func secretKeys(of type: String) -> Set<String> {
        switch type {
        case basicAuth: ["password"]
        case totp: ["secret"]
        case creditCard: ["number", "verificationNumber", "pin"]
        case passport, driversLicense, identityDocument: ["documentNumber"]
        case sshKey: ["privateKey"]
        default: []
        }
    }
}

/// Types of a custom field (`VAULT.md` § 9.2).
nonisolated enum VaultFieldType: String, CaseIterable, Sendable {
    case text
    case concealed
    case url
    case email
    case phone
    case date
    case totp

    /// A concealed field or a one-time code: a secret.
    var isSecret: Bool {
        self == .concealed || self == .totp
    }
}
