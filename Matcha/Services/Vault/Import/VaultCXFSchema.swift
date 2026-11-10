import Foundation

/// How the items of the vault map to those of the Credential Exchange Format (CXF 1.0, FIDO Alliance, proposed standard
/// of 2025-08-14 and its errata of 2026-03-09; `VAULT.md` § 9): the same credential types and, for most, the same keys,
/// whose values CXF writes as `EditableField`s of a field type. Shared by `VaultCXFReader` and `VaultCXFWriter`. Pure
/// type.
nonisolated enum VaultCXFSchema {
    static let majorVersion = 1
    static let minorVersion = 0
    /// The exporter, as a relying party identifier (the domain of the bundle identifier).
    static let exporterRpID = "matchabrowser.com"
    static let exporterDisplayName = "Matcha"
    /// Our extensions (CXF § 3.5: `EXPORTER_RP_ID/EXTENSION_NAME`): the type of a custom field CXF has no field type for
    /// (`url`, `phone`, `totp`), and the match of the addresses of a login (`VAULT.md` § 8.2) when it isn't `site`.
    static let fieldTypeExtension = "\(exporterRpID)/field-type"
    static let urlMatchExtension = "\(exporterRpID)/url-match"

    /// Credential types read and written key by key, each value an `EditableField`.
    static let editableTypes: Set<String> = [
        VaultCredentialType.creditCard, VaultCredentialType.personName, VaultCredentialType.address, VaultCredentialType.passport,
        VaultCredentialType.driversLicense, VaultCredentialType.identityDocument,
    ]

    /// Our keys that CXF names otherwise, by credential type: the number and country of a document (`VAULT.md` § 9.3).
    private static let renamed: [String: [String: String]] = [
        VaultCredentialType.passport: ["documentNumber": "passportNumber"],
        VaultCredentialType.driversLicense: ["documentNumber": "licenseNumber", "issuingCountry": "country"],
    ]

    static func cxfKey(_ key: String, type: String) -> String {
        renamed[type]?[key] ?? key
    }

    static func vaultKey(_ key: String, type: String) -> String {
        renamed[type]?.first { $0.value == key }?.key ?? key
    }

    /// The field type CXF expects for the key `key` (its own name) of a credential of `type`.
    static func fieldType(ofKey key: String, type: String) -> String {
        if type == VaultCredentialType.creditCard {
            switch key {
            case "number", "verificationNumber", "pin": return "concealed-string"
            case "expiryDate", "validFrom": return "year-month"
            default: break
            }
        }
        return switch key {
        case "country", "issuingCountry":
            "country-code"
        case "territory":
            "subdivision-code"
        case _ where key.hasSuffix("Date"):
            "date"
        default:
            "string"
        }
    }

    // MARK: Custom fields

    /// The CXF field type of a custom field; nil for the types CXF lacks, written as `string` (or `concealed-string`
    /// for a one-time code) with our extension.
    static func cxfFieldType(of type: VaultFieldType) -> String? {
        switch type {
        case .text: "string"
        case .concealed: "concealed-string"
        case .email: "email"
        case .date: "date"
        case .url, .phone, .totp: nil
        }
    }

    /// The type of a custom field read from CXF: its field type, or our extension; text for any other (CXF § 3.4.2).
    static func vaultFieldType(_ cxfType: String, extensionType: String?) -> VaultFieldType {
        if let extensionType, let type = VaultFieldType(rawValue: extensionType) {
            return type
        }
        return switch cxfType {
        case "concealed-string": .concealed
        case "email": .email
        case "date": .date
        default: .text
        }
    }

    // MARK: Categories

    /// The category of an item read from CXF, which has none: by its credentials, first the login, then the card, the
    /// document, the identity and the SSH key; then custom fields, notes.
    static func category(of details: VaultDetails, hasURLs: Bool) -> VaultCategory {
        let types = Set(details.credentials.map { $0.string("type") })
        let order: [(Set<String>, VaultCategory)] = [
            ([VaultCredentialType.basicAuth, VaultCredentialType.totp], .login),
            ([VaultCredentialType.creditCard], .card),
            ([VaultCredentialType.passport, VaultCredentialType.driversLicense, VaultCredentialType.identityDocument], .document),
            ([VaultCredentialType.personName, VaultCredentialType.address], .identity),
            ([VaultCredentialType.sshKey], .sshKey),
        ]
        if let match = order.first(where: { !$0.0.isDisjoint(with: types) }) {
            return match.1
        }
        if hasURLs {
            return .login
        }
        return details.fields.isEmpty && !details.notes.isEmpty ? .note : .custom
    }

    // MARK: Identifiers

    /// Base 64 URL-safe without padding (RFC 4648 § 5), as CXF writes its `b64url`.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64URL text: String) -> Data? {
        var base64 = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
