import Foundation

/// A field of the form of an item, by category (`VAULT.md` § 9.3): the credential it belongs to, its key there, and
/// how it is typed and shown. The interface gives each its label.
nonisolated struct VaultFieldSpec: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case text
        /// Masked, copied as a secret, kept in the history (`VAULT.md` § 9.5).
        case secret
        /// A secret on several lines (a private key).
        case secretText
        /// `AAAA-MM-JJ`.
        case date
        /// `AAAA-MM`.
        case month
        /// A one-time code: its secret, or its `otpauth://` address.
        case oneTimeCode
        /// Shown, not typed (a public key, a fingerprint).
        case readOnly
    }

    /// Credential type (`VaultCredentialType`), and key in it.
    let credential: String
    let key: String
    let kind: Kind

    /// Identifier of the field in a draft: `<credential>.<key>`.
    var id: String {
        "\(credential).\(key)"
    }

    static func fields(of category: VaultCategory, document: String = VaultCredentialType.identityDocument) -> [VaultFieldSpec] {
        switch category {
        case .login: login
        case .card: card
        case .identity: identity
        case .document: Self.document(document)
        case .sshKey: sshKey
        case .note, .file, .custom, .unknown: []
        }
    }

    static let login = [
        VaultFieldSpec(credential: VaultCredentialType.basicAuth, key: "username", kind: .text),
        VaultFieldSpec(credential: VaultCredentialType.basicAuth, key: "password", kind: .secret),
        VaultFieldSpec(credential: VaultCredentialType.totp, key: "secret", kind: .oneTimeCode),
    ]

    static let card = ["fullName", "cardType", "number", "expiryDate", "validFrom", "verificationNumber", "pin"].map { key in
        VaultFieldSpec(credential: VaultCredentialType.creditCard, key: key, kind: cardKind(key))
    }

    private static func cardKind(_ key: String) -> Kind {
        switch key {
        case "number", "verificationNumber", "pin": .secret
        case "expiryDate", "validFrom": .month
        default: .text
        }
    }

    static let identity = ["title", "given", "given2", "surname"].map {
        VaultFieldSpec(credential: VaultCredentialType.personName, key: $0, kind: .text)
    } + ["streetAddress", "postalCode", "city", "territory", "country", "tel"].map {
        VaultFieldSpec(credential: VaultCredentialType.address, key: $0, kind: .text)
    }

    static func document(_ type: String) -> [VaultFieldSpec] {
        ["documentNumber", "fullName", "birthDate", "issueDate", "expiryDate", "issuingCountry", "issuingAuthority"].map { key in
            let kind: Kind = switch key {
            case "documentNumber": .secret
            case "birthDate", "issueDate", "expiryDate": .date
            default: .text
            }
            return VaultFieldSpec(credential: type, key: key, kind: kind)
        }
    }

    static let documentTypes = [VaultCredentialType.passport, VaultCredentialType.driversLicense, VaultCredentialType.identityDocument]

    static let sshKey = [
        VaultFieldSpec(credential: VaultCredentialType.sshKey, key: "privateKey", kind: .secretText),
        VaultFieldSpec(credential: VaultCredentialType.sshKey, key: "publicKey", kind: .readOnly),
        VaultFieldSpec(credential: VaultCredentialType.sshKey, key: "fingerprint", kind: .readOnly),
        VaultFieldSpec(credential: VaultCredentialType.sshKey, key: "keyComment", kind: .text),
    ]
}
