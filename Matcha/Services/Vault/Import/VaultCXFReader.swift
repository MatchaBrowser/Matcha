import Foundation

/// Imports a CXF document (`VaultCXFSchema`): the items of every account, their title, addresses (`scope.urls`), tags
/// (and the titles of their collections), favorite mark and creation date. The credential types of the vault keep
/// their keys (`basic-auth`, `totp`, `credit-card`, `person-name`, `address`, documents, `ssh-key` turned into the
/// OpenSSH format); `note` goes into the notes, `custom-fields` into the fields, `generated-password` into the login,
/// and any other type with `EditableField`s (`wifi`, `api-key`…) into custom fields. Files, passkeys and the rest are
/// reported. Also the content of our `.matchavault` files. Pure type.
nonisolated enum VaultCXFReader {
    /// Nesting of collections followed at most.
    private static let maximumCollectionDepth = 16

    /// Whether `json` looks like a CXF header.
    static func isDocument(_ json: VaultImportJSON) -> Bool {
        json["version"].isObject && json["accounts"].isArray
    }

    static func read(_ data: Data) throws -> VaultImportResult {
        guard data.count <= VaultImportLimits.maximumCXFBytes else {
            throw VaultImportError.tooLarge
        }
        let json = try VaultImportJSON(data: data)
        guard isDocument(json) else {
            throw VaultImportError.unknownFormat
        }
        guard json["version"]["major"].integer == VaultCXFSchema.majorVersion else {
            throw VaultImportError.unsupportedVersion
        }
        var result = VaultImportResult()
        var position = 0
        for account in json["accounts"].array {
            var tags: [String: [String]] = [:]
            collectionTitles(account["collections"], depth: 0, into: &tags)
            for item in account["items"].array {
                position += 1
                result.add(draft(of: item, position: position, collections: tags[item["id"].string] ?? []))
            }
        }
        return result
    }

    /// The titles of the collections of each item, by item `id`, sub-collections included.
    private static func collectionTitles(_ collections: VaultImportJSON, depth: Int, into titles: inout [String: [String]]) {
        guard depth < maximumCollectionDepth else {
            return
        }
        for collection in collections.array {
            for linked in collection["items"].array {
                titles[linked["item"].string, default: []].append(collection["title"].string)
            }
            collectionTitles(collection["subCollections"], depth: depth + 1, into: &titles)
        }
    }

    /// The draft of one item.
    static func draft(of item: VaultImportJSON, position: Int, collections: [String] = []) -> VaultImportDraft {
        var draft = VaultImportDraft(position: position, title: item["title"].string)
        guard item.isObject else {
            draft.skipReason = .unreadable
            return draft
        }
        draft.content.overview.subtitle = item["subtitle"].string
        draft.content.overview.favorite = item["favorite"].bool ?? false
        (item["tags"].array.map(\.string) + collections).forEach { draft.addTag($0) }
        item["scope"]["urls"].array.forEach { draft.addURL($0.string) }
        draft.content.details.createdAt = item["creationAt"].date()
        for credential in item["credentials"].array {
            read(credential, into: &draft)
        }
        let match = item["extensions"].array.first { $0["name"].string == VaultCXFSchema.urlMatchExtension }
        draft.content.overview.match = match.flatMap { VaultURLMatch(rawValue: $0["match"].string) } ?? .site
        draft.category = VaultCXFSchema.category(of: draft.content.details, hasURLs: !draft.content.overview.urls.isEmpty)
        return draft
    }

    // MARK: Credentials

    private static func read(_ credential: VaultImportJSON, into draft: inout VaultImportDraft) {
        let type = credential["type"].string
        switch type {
        case VaultCredentialType.basicAuth:
            let values = ["username": credential["username"]["value"].string, "password": credential["password"]["value"].string]
            draft.addCredential(type, values)
        case VaultCredentialType.totp:
            readOneTimeCode(credential, into: &draft)
        case _ where VaultCXFSchema.editableTypes.contains(type):
            let values = editableValues(of: credential).map { (VaultCXFSchema.vaultKey($0.key, type: type), $0.field["value"].string) }
            draft.addCredential(type, Dictionary(values, uniquingKeysWith: { first, _ in first }))
        case VaultCredentialType.sshKey:
            readSSHKey(credential, into: &draft)
        case "note":
            draft.addNotes(credential["content"]["value"].string)
        case "custom-fields":
            for field in credential["fields"].array {
                addField(field, label: field["label"].string.isEmpty ? credential["label"].string : field["label"].string, to: &draft)
            }
        default:
            readOther(credential, type: type, into: &draft)
        }
    }

    /// A `totp` credential; one of an algorithm, a length or a period Matcha doesn't compute is left out (CXF
    /// § 3.3.16) and reported.
    private static func readOneTimeCode(_ credential: VaultImportJSON, into draft: inout VaultImportDraft) {
        var setup = VaultOTPAuth.Setup(secret: credential["secret"].string)
        setup.algorithm = credential["algorithm"].isNull ? "sha1" : credential["algorithm"].string
        setup.digits = credential["digits"].isNull ? 6 : credential["digits"].integer ?? 0
        setup.period = credential["period"].isNull ? 30 : credential["period"].integer ?? 0
        setup.issuer = credential["issuer"].string
        if let entry = setup.credential {
            draft.addCredential(entry)
        } else {
            draft.issues.append(.invalidOneTimeCode)
        }
    }

    /// An `ssh-key`: its PKCS#8 private key in the OpenSSH format, and its other values kept on the credential.
    private static func readSSHKey(_ credential: VaultImportJSON, into draft: inout VaultImportDraft) {
        let comment = credential["keyComment"].string
        let count = draft.content.details.credentials.count
        if let der = VaultCXFSchema.data(base64URL: credential["privateKey"].string), !der.isEmpty {
            draft.addSSHKey(pkcs8: der, comment: comment)
        } else {
            draft.addSSHKey(privateKey: credential["privateKey"].string, comment: comment)
        }
        guard draft.content.details.credentials.count > count, let index = draft.content.details.credentials.indices.last else {
            return
        }
        for (key, field) in editableValues(of: credential) {
            draft.content.details.credentials[index].set(key, field["value"].string)
        }
    }

    /// A credential of a type the vault has no place for: a generated password goes into the login, a file or a
    /// passkey is reported, and any other type gives its `EditableField`s as custom fields, or is reported.
    private static func readOther(_ credential: VaultImportJSON, type: String, into draft: inout VaultImportDraft) {
        let fields = editableValues(of: credential)
        switch type {
        case "generated-password" where draft.content.details.credential(VaultCredentialType.basicAuth) == nil:
            draft.addCredential(VaultCredentialType.basicAuth, ["password": credential["password"].string])
        case "generated-password":
            draft.addField(label: "password", type: .concealed, value: credential["password"].string)
        case "file":
            draft.issues.append(.attachment)
        case "passkey":
            draft.issues.append(.passkey)
        case _ where fields.isEmpty:
            draft.issues.append(.unsupportedType(type))
        default:
            for (key, field) in fields {
                addField(field, label: field["label"].string.isEmpty ? key : field["label"].string, to: &draft)
            }
        }
    }

    private static func addField(_ field: VaultImportJSON, label: String, to draft: inout VaultImportDraft) {
        let ours = field["extensions"].array.first { $0["name"].string == VaultCXFSchema.fieldTypeExtension }
        let type = VaultCXFSchema.vaultFieldType(field["fieldType"].string, extensionType: ours?["type"].string)
        draft.addField(label: label, type: type, value: field["value"].string)
    }

    /// The members of `credential` that are `EditableField`s (an object with a `fieldType` and a text `value`), by key.
    private static func editableValues(of credential: VaultImportJSON) -> [(key: String, field: VaultImportJSON)] {
        credential.keys.compactMap { key in
            let field = credential[key]
            return field.isObject && !field["fieldType"].isNull && field["value"].isText ? (key, field) : nil
        }
    }
}
