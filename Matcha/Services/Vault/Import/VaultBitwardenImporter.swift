import Foundation

/// Imports an unencrypted JSON export of Bitwarden (`VAULT.md` § 10): `{ "encrypted": false, "folders": […],
/// "items": […] }`, or `collections` for an organization. Logins (type 1), secure notes (2), cards (3), identities (4)
/// and SSH keys (5) are imported, with their custom fields, notes, favorite mark and creation date; a folder or a
/// collection becomes a tag. Other types, linked fields and passkeys are reported; an encrypted export is refused
/// (`VaultImportError.encryptedExport`). Pure type.
nonisolated enum VaultBitwardenImporter {
    /// A value of an identity that has no place in a credential of Matcha: a custom field.
    private struct IdentityField {
        let key: String
        /// Its label: data of the item, written in English (Bitwarden gives none).
        let label: String
        let type: VaultFieldType
    }

    private static let identityFields = [
        IdentityField(key: "email", label: "Email", type: .email),
        IdentityField(key: "phone", label: "Phone", type: .phone),
        IdentityField(key: "company", label: "Company", type: .text),
        IdentityField(key: "username", label: "Username", type: .text),
        IdentityField(key: "ssn", label: "Social Security number", type: .concealed),
        IdentityField(key: "passportNumber", label: "Passport number", type: .concealed),
        IdentityField(key: "licenseNumber", label: "License number", type: .concealed),
    ]

    /// Whether `json` is a Bitwarden export, encrypted or not.
    static func isExport(_ json: VaultImportJSON) -> Bool {
        json["encrypted"].bool != nil || (json["items"].isArray && json["folders"].isArray)
    }

    /// The items of an export.
    static func read(_ data: Data) throws -> VaultImportResult {
        guard data.count <= VaultImportLimits.maximumTextBytes else {
            throw VaultImportError.tooLarge
        }
        let json = try VaultImportJSON(data: data)
        guard isExport(json) else {
            throw VaultImportError.unknownFormat
        }
        guard json["encrypted"].bool != true, json["passwordProtected"].bool != true else {
            throw VaultImportError.encryptedExport
        }
        guard json["items"].isArray else {
            throw VaultImportError.unreadable
        }
        let groups = (json["folders"].array + json["collections"].array).map { ($0["id"].string, $0["name"].string) }
        let names = Dictionary(groups, uniquingKeysWith: { first, _ in first })
        var result = VaultImportResult()
        for (index, item) in json["items"].array.enumerated() {
            result.add(draft(of: item, position: index + 1, groups: names))
        }
        return result
    }

    /// The draft of one item; `groups`: names of the folders and collections by `id`.
    static func draft(of item: VaultImportJSON, position: Int, groups: [String: String]) -> VaultImportDraft {
        var draft = VaultImportDraft(position: position, title: item["name"].string)
        guard item.isObject else {
            draft.skipReason = .unreadable
            return draft
        }
        draft.content.overview.favorite = item["favorite"].bool ?? false
        draft.content.details.createdAt = SyncCoding.date(from: item["creationDate"].string)
        for id in [item["folderId"].string] + item["collectionIds"].array.map(\.string) {
            draft.addTag(groups[id] ?? "")
        }
        switch item["type"].integer {
        case 1:
            addLogin(of: item, to: &draft)
        case 2:
            draft.category = .note
        case 3:
            addCard(item["card"], to: &draft)
        case 4:
            addIdentity(item["identity"], to: &draft)
        case 5:
            let key = item["sshKey"]
            let privateKey = key["privateKey"].string
            draft.addSSHKey(privateKey: privateKey, publicKey: key["publicKey"].string, fingerprint: key["keyFingerprint"].string)
        default:
            draft.skipReason = .unsupportedType(item["type"].string)
            return draft
        }
        addFields(item["fields"], to: &draft)
        draft.addNotes(item["notes"].string)
        return draft
    }

    // MARK: Types

    private static func addLogin(of item: VaultImportJSON, to draft: inout VaultImportDraft) {
        let login = item["login"]
        draft.category = .login
        let uris = login["uris"].array
        for uri in uris {
            draft.addURL(uri["uri"].string)
        }
        // Bitwarden's match of the first address: 1 host, 3 exact; the others are closest to the site.
        draft.content.overview.match = switch uris.first?["match"].integer {
        case 1: .host
        case 3: .page
        default: .site
        }
        let values = ["username": login["username"].string, "password": login["password"].string]
        let id = draft.addCredential(VaultCredentialType.basicAuth, values)
        let totp = login["totp"].string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let credential = VaultOTPAuth.credential(from: totp) {
            draft.addCredential(credential)
        } else if !totp.isEmpty {
            draft.issues.append(.invalidOneTimeCode)
        }
        if !login["fido2Credentials"].array.isEmpty {
            draft.issues.append(.passkey)
        }
        if let id {
            let history = item["passwordHistory"].array.compactMap { entry in
                SyncCoding.date(from: entry["lastUsedDate"].string).map { (value: entry["password"].string, date: $0) }
            }
            draft.addPasswordHistory(history, credentialID: id)
        }
    }

    private static func addCard(_ card: VaultImportJSON, to draft: inout VaultImportDraft) {
        draft.category = .card
        draft.addCredential(VaultCredentialType.creditCard, [
            "fullName": card["cardholderName"].string,
            "cardType": card["brand"].string,
            "number": card["number"].string,
            "expiryDate": expiryDate(month: card["expMonth"].string, year: card["expYear"].string),
            "verificationNumber": card["code"].string,
        ])
    }

    /// `YYYY-MM` from a month (`4`, `04`) and a year (`2027`, `27`); empty if either is unreadable.
    static func expiryDate(month: String, year: String) -> String {
        guard let month = Int(month.trimmingCharacters(in: .whitespaces)), (1 ... 12).contains(month),
              var year = Int(year.trimmingCharacters(in: .whitespaces)), year >= 0
        else {
            return ""
        }
        if year < 100 {
            year += 2000
        }
        guard year <= 9999 else {
            return ""
        }
        return String(format: "%04ld-%02ld", year, month)
    }

    private static func addIdentity(_ identity: VaultImportJSON, to draft: inout VaultImportDraft) {
        draft.category = .identity
        draft.addCredential(VaultCredentialType.personName, [
            "title": identity["title"].string,
            "given": identity["firstName"].string,
            "given2": identity["middleName"].string,
            "surname": identity["lastName"].string,
        ])
        let street = ["address1", "address2", "address3"].map { identity[$0].string }.filter { !$0.isEmpty }
        draft.addCredential(VaultCredentialType.address, [
            "streetAddress": street.joined(separator: "\n"),
            "postalCode": identity["postalCode"].string,
            "city": identity["city"].string,
            "territory": identity["state"].string,
            "country": identity["country"].string,
        ])
        for field in identityFields {
            draft.addField(label: field.label, type: field.type, value: identity[field.key].string)
        }
    }

    /// Custom fields: text (0), hidden (1, concealed), boolean (2, `true` or `false`); linked fields (3) are reported.
    private static func addFields(_ fields: VaultImportJSON, to draft: inout VaultImportDraft) {
        for field in fields.array {
            let label = field["name"].string
            let value = field["value"].string
            switch field["type"].integer {
            case 0:
                draft.addField(label: label, type: .text, value: value)
            case 1:
                draft.addField(label: label, type: .concealed, value: value)
            case 2:
                draft.addField(label: label, type: .text, value: value.lowercased() == "true" ? "true" : "false")
            case 3:
                draft.issues.append(.linkedField)
            default:
                draft.issues.append(.unsupportedField(field["type"].string))
            }
        }
    }
}
