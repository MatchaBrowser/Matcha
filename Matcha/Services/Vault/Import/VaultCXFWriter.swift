import Foundation

/// Writes items of the vault as a CXF document (`VaultCXFSchema`, `VAULT.md` § 10), read back by `VaultCXFReader`:
/// one account, and for each item its title, subtitle, addresses (`scope`), tags, favorite mark and dates; the
/// credentials of the vault with CXF's `EditableField`s (an SSH key in PKCS#8), the custom fields in one
/// `custom-fields`, the notes in a `note`. Files are left out, and counted for the interface to say so. JSON with sorted
/// keys, `/` not escaped, at most `VaultImportLimits.maximumCXFBytes`: what Matcha writes, it reads again. Pure type.
nonisolated enum VaultCXFWriter {
    struct Export: Equatable, Sendable {
        let data: Data
        /// Files of the items left out (`VAULT.md` § 6).
        let omittedFiles: Int
    }

    /// Keys of an `ssh-key` CXF writes in its own way, or not at all (computed again on reading).
    private static let sshKeyKeys: Set<String> = ["id", "type", "keyType", "privateKey", "publicKey", "fingerprint", "keyComment"]

    /// The document of `items`, dated `date`.
    static func export(_ items: [VaultItemContent], at date: Date = .now) throws -> Export {
        let account: [String: SyncJSON] = [
            "id": randomID(), "username": .string(""), "email": .string(""), "collections": .array([]), "items": .array(items.map(json)),
        ]
        let version: [String: SyncJSON] = [
            "major": .number(Double(VaultCXFSchema.majorVersion)), "minor": .number(Double(VaultCXFSchema.minorVersion)),
        ]
        let header = SyncJSON.object([
            "version": .object(version),
            "exporterRpId": .string(VaultCXFSchema.exporterRpID),
            "exporterDisplayName": .string(VaultCXFSchema.exporterDisplayName),
            "timestamp": seconds(date),
            "accounts": .array([.object(account)]),
        ])
        let data = try SyncCoding.encoder().encode(header)
        guard data.count <= VaultImportLimits.maximumCXFBytes else {
            throw VaultExportError.tooLarge
        }
        return Export(data: data, omittedFiles: items.reduce(0) { $0 + $1.details.files.count })
    }

    /// The CXF `Item` of one item; optional arrays are left out when empty (CXF § 2.1.2).
    static func json(of item: VaultItemContent) -> SyncJSON {
        let overview = item.overview
        var object: [String: SyncJSON] = [
            "id": randomID(), "title": .string(overview.title), "credentials": .array(credentials(of: item.details)),
        ]
        if !overview.subtitle.isEmpty {
            object["subtitle"] = .string(overview.subtitle)
        }
        if overview.favorite {
            object["favorite"] = .bool(true)
        }
        if !overview.tags.isEmpty {
            object["tags"] = .array(overview.tags.map(SyncJSON.string))
        }
        if !overview.urls.isEmpty {
            object["scope"] = .object(["urls": .array(overview.urls.map(SyncJSON.string)), "androidApps": .array([])])
        }
        object["creationAt"] = item.details.createdAt.map(seconds)
        object["modifiedAt"] = overview.modifiedAt.map(seconds)
        if overview.match != .site {
            let match: [String: SyncJSON] = ["name": .string(VaultCXFSchema.urlMatchExtension), "match": .string(overview.match.rawValue)]
            object["extensions"] = .array([.object(match)])
        }
        return .object(object)
    }

    // MARK: Credentials

    private static func credentials(of details: VaultDetails) -> [SyncJSON] {
        var credentials: [SyncJSON] = []
        var fields = details.fields.compactMap(customField)
        for entry in details.credentials {
            if let credential = credential(of: entry) {
                credentials.append(credential)
            } else {
                // An SSH key this version can't write in PKCS#8: its values as custom fields, so that none is lost.
                fields += entry.keys.filter { $0 != "id" && $0 != "type" && !entry.string($0).isEmpty }.map { key in
                    editableField(key == "privateKey" ? "concealed-string" : "string", entry.string(key), label: key)
                }
            }
        }
        if !fields.isEmpty {
            credentials.append(.object(["type": .string("custom-fields"), "fields": .array(fields)]))
        }
        if !details.notes.isEmpty {
            credentials.append(.object(["type": .string("note"), "content": editableField("string", details.notes)]))
        }
        return credentials
    }

    /// The CXF credential of one of ours; nil for an SSH key that can't be read.
    private static func credential(of entry: VaultEntry) -> SyncJSON? {
        let type = entry.string("type")
        var object: [String: SyncJSON] = ["type": .string(type)]
        switch type {
        case VaultCredentialType.basicAuth:
            object["username"] = entry.string("username").isEmpty ? nil : editableField("string", entry.string("username"))
            object["password"] = entry.string("password").isEmpty ? nil : editableField("concealed-string", entry.string("password"))
        case VaultCredentialType.totp:
            object["secret"] = .string(entry.string("secret"))
            object["algorithm"] = .string(entry.string("algorithm").isEmpty ? "sha1" : entry.string("algorithm"))
            object["digits"] = .number(Double(entry.integer("digits") ?? 6))
            object["period"] = .number(Double(entry.integer("period") ?? 30))
            object["issuer"] = entry.string("issuer").isEmpty ? nil : .string(entry.string("issuer"))
        case VaultCredentialType.sshKey:
            guard let key = VaultSSHKey(text: entry.string("privateKey"), comment: entry.string("keyComment")), let der = key.pkcs8 else {
                return nil
            }
            object["keyType"] = .string(key.keyType)
            object["privateKey"] = .string(VaultCXFSchema.base64URL(der))
            object["keyComment"] = key.comment.isEmpty ? nil : .string(key.comment)
            for key in entry.keys where !sshKeyKeys.contains(key) && !entry.string(key).isEmpty {
                object[key] = editableField(VaultCXFSchema.fieldType(ofKey: key, type: type), entry.string(key))
            }
        default:
            // The other types of the vault, and those of a newer version: each text as an `EditableField`.
            for key in entry.keys where key != "id" && key != "type" && !entry.string(key).isEmpty {
                let cxfKey = VaultCXFSchema.cxfKey(key, type: type)
                object[cxfKey] = editableField(VaultCXFSchema.fieldType(ofKey: cxfKey, type: type), entry.string(key))
            }
        }
        return .object(object)
    }

    /// A custom field as an `EditableField`, with our extension when CXF has no field type for it.
    private static func customField(_ field: VaultEntry) -> SyncJSON? {
        guard !field.string("value").isEmpty else {
            return nil
        }
        let type = VaultFieldType(rawValue: field.string("type")) ?? .text
        let cxfType = VaultCXFSchema.cxfFieldType(of: type)
        let fieldType = cxfType ?? (type.isSecret ? "concealed-string" : "string")
        var object = editableField(fieldType, field.string("value"), label: field.string("label")).objectValue
        if cxfType == nil {
            let ours: [String: SyncJSON] = ["name": .string(VaultCXFSchema.fieldTypeExtension), "type": .string(type.rawValue)]
            object["extensions"] = .array([.object(ours)])
        }
        return .object(object)
    }

    private static func editableField(_ fieldType: String, _ value: String, label: String = "") -> SyncJSON {
        var object: [String: SyncJSON] = ["fieldType": .string(fieldType), "value": .string(value)]
        if !label.isEmpty {
            object["label"] = .string(label)
        }
        return .object(object)
    }

    // MARK: Values

    /// A whole number of seconds since 1970 (CXF's `uint` timestamps).
    private static func seconds(_ date: Date) -> SyncJSON {
        .number(max(0, date.timeIntervalSince1970.rounded(.down)))
    }

    /// A random identifier of 16 bytes, in `b64url` (CXF § 1.3).
    private static func randomID() -> SyncJSON {
        .string(VaultCXFSchema.base64URL(SyncCrypto.randomBytes(16)))
    }
}
