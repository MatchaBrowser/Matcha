import Foundation

/// One item of a 1PUX export, read into a draft. By `categoryUuid`: 001 login and 005 password (`basic-auth`, the
/// first one-time code as a `totp` credential), 002 credit card (`credit-card`), 003 secure note, 004 identity
/// (`person-name`, `address`), 114 SSH key (`ssh-key`); 006 document is not imported (attachments), and any other
/// category becomes a custom item. The values that have no place in a credential become custom fields, labelled with
/// their 1Password title. Pure type.
nonisolated struct Vault1PUXItem {
    private(set) var draft: VaultImportDraft
    private let category: VaultCategory?
    private var username = ""
    private var password = ""
    /// Values of the credit card and of the name, by our keys.
    private var card: [String: String] = [:]
    private var name: [String: String] = [:]

    private static let categories: [String: VaultCategory] = [
        "001": .login, "002": .card, "003": .note, "004": .identity, "005": .login, "114": .sshKey,
    ]
    /// Card fields by 1Password `id`.
    private static let cardKeys = [
        "cardholder": "fullName", "type": "cardType", "ccnum": "number", "cvv": "verificationNumber", "expiry": "expiryDate",
        "validFrom": "validFrom", "pin": "pin",
    ]
    /// Name fields of an identity by 1Password `id`.
    private static let nameKeys = ["firstname": "given", "initial": "given2", "lastname": "surname"]

    init(_ item: VaultImportJSON, position: Int) {
        let overview = item["overview"]
        let details = item["details"]
        category = Self.categories[item["categoryUuid"].string]
        draft = VaultImportDraft(position: position, title: overview["title"].string, category: category ?? .custom)
        guard item.isObject, item["categoryUuid"].string != "006" else {
            draft.skipReason = item.isObject ? .attachment : .unreadable
            return
        }
        draft.content.overview.favorite = (item["favIndex"].integer ?? 0) > 0
        overview["tags"].array.forEach { draft.addTag($0.string) }
        overview["urls"].array.forEach { draft.addURL($0["url"].string) }
        draft.addURL(overview["url"].string)
        draft.content.details.createdAt = item["createdAt"].date()
        readLoginFields(details["loginFields"])
        if item["categoryUuid"].string == "005" {
            password = details["password"].string
        }
        for section in details["sections"].array {
            section["fields"].array.forEach { read($0) }
        }
        finish(history: details["passwordHistory"])
        draft.addNotes(details["notesPlain"].string)
    }

    // MARK: Reading

    /// The fields of a login form: user name and password by their designation, the others as custom fields.
    private mutating func readLoginFields(_ fields: VaultImportJSON) {
        for field in fields.array {
            let value = field["value"].string
            let label = field["name"].string.isEmpty ? field["id"].string : field["name"].string
            switch (field["designation"].string, field["fieldType"].string) {
            case ("username", _) where username.isEmpty:
                username = value
            case ("password", _) where password.isEmpty:
                password = value
            case (_, "P"):
                draft.addField(label: label, type: .concealed, value: value)
            case (_, "E"):
                draft.addField(label: label, type: .email, value: value)
            case (_, "U"):
                draft.addField(label: label, type: .url, value: value)
            case (_, "TEL"):
                draft.addField(label: label, type: .phone, value: value)
            case (_, "C"):
                draft.addField(label: label, type: .text, value: value.isEmpty ? "" : "true")
            default:
                draft.addField(label: label, type: .text, value: value)
            }
        }
    }

    /// A field of a section: into a credential of the item when it has a place there, a custom field otherwise.
    private mutating func read(_ field: VaultImportJSON) {
        let id = field["id"].string
        let label = field["title"].string.isEmpty ? id : field["title"].string
        let value = field["value"]
        guard let kind = value.keys.first(where: { !value[$0].isNull }) else {
            return
        }
        let text = Self.text(of: value[kind], kind: kind)
        guard !place(text, id: id, label: label, kind: kind) else {
            return
        }
        switch kind {
        case "address":
            addAddress(value[kind], label: label)
        case "sshKey":
            let key = value[kind]
            let metadata = key["metadata"]
            let privateKey = metadata["privateKey"].string.isEmpty ? key["privateKey"].string : metadata["privateKey"].string
            draft.addSSHKey(privateKey: privateKey, publicKey: metadata["publicKey"].string, fingerprint: metadata["fingerprint"].string)
        default:
            addField(kind: kind, text: text, label: label)
        }
    }

    /// Puts a value into the login, card or name of the item; false when it has no place there.
    private mutating func place(_ text: String, id: String, label: String, kind: String) -> Bool {
        switch category {
        case .login where kind == "totp" && draft.content.details.credential(VaultCredentialType.totp) == nil:
            addOneTimeCode(text, label: label, asCredential: true)
        case .login where label.lowercased() == "username" && username.isEmpty:
            username = text
        case .login where label.lowercased() == "password" && password.isEmpty:
            password = text
        case .card where Self.cardKeys[id] != nil:
            card[Self.cardKeys[id] ?? id] = text
        case .identity where Self.nameKeys[id] != nil:
            name[Self.nameKeys[id] ?? id] = text
        default:
            return false
        }
        return true
    }

    private mutating func addField(kind: String, text: String, label: String) {
        switch kind {
        case "string", "menu", "gender", "creditCardType", "monthYear":
            draft.addField(label: label, type: .text, value: text)
        case "concealed", "creditCardNumber":
            draft.addField(label: label, type: .concealed, value: text)
        case "email":
            draft.addField(label: label, type: .email, value: text)
        case "phone":
            draft.addField(label: label, type: .phone, value: text)
        case "url":
            draft.addField(label: label, type: .url, value: text)
        case "date":
            draft.addField(label: label, type: .date, value: text)
        case "totp":
            addOneTimeCode(text, label: label, asCredential: false)
        case "file":
            draft.issues.append(.attachment)
        default:
            draft.issues.append(.unsupportedField(kind))
        }
    }

    /// The first code of a login is its `totp` credential; any other is a `totp` field, as an `otpauth://` address.
    private mutating func addOneTimeCode(_ text: String, label: String, asCredential: Bool) {
        guard let credential = VaultOTPAuth.credential(from: text) else {
            if !text.isEmpty {
                draft.issues.append(.invalidOneTimeCode)
            }
            return
        }
        if asCredential {
            draft.addCredential(credential)
        } else {
            let uri = text.lowercased().hasPrefix("otpauth:") ? text : "otpauth://totp/?secret=" + credential.string("secret")
            draft.addField(label: label, type: .totp, value: uri)
        }
    }

    /// An address: the `address` credential of an identity; a text field in any other item.
    private mutating func addAddress(_ address: VaultImportJSON, label: String) {
        let values = [
            "streetAddress": address["street"].string, "postalCode": address["zip"].string, "city": address["city"].string,
            "territory": address["state"].string, "country": address["country"].string.uppercased(),
        ]
        if category == .identity, draft.content.details.credential(VaultCredentialType.address) == nil {
            draft.addCredential(VaultCredentialType.address, values)
        } else {
            let parts = ["streetAddress", "postalCode", "city", "territory", "country"].compactMap { values[$0] }
            draft.addField(label: label, type: .text, value: parts.filter { !$0.isEmpty }.joined(separator: "\n"))
        }
    }

    /// The credentials gathered from the fields; outside a login, a user name and a password stay custom fields.
    private mutating func finish(history: VaultImportJSON) {
        if category == .login {
            if let id = draft.addCredential(VaultCredentialType.basicAuth, ["username": username, "password": password]) {
                let passwords = history.array.compactMap { entry in entry["time"].date().map { (value: entry["value"].string, date: $0) } }
                draft.addPasswordHistory(passwords, credentialID: id)
            }
        } else {
            draft.addField(label: "username", type: .text, value: username)
            draft.addField(label: "password", type: .concealed, value: password)
        }
        draft.addCredential(VaultCredentialType.creditCard, card)
        draft.addCredential(VaultCredentialType.personName, name)
    }

    // MARK: Values

    /// The value of a field as text: the address of an e-mail object, a date as `YYYY-MM-DD`, a month (`202708`) as
    /// `YYYY-MM`.
    private static func text(of value: VaultImportJSON, kind: String) -> String {
        switch kind {
        case "email":
            return value.isObject ? value["email_address"].string : value.string
        case "date":
            // Seconds since 1970, before it for a birth date.
            guard let seconds = value.number, abs(seconds) < 1e11 else {
                return ""
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            let day = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: seconds))
            return String(format: "%04ld-%02ld-%02ld", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        case "monthYear":
            guard let value = value.integer, (1 ... 12).contains(value % 100), (1000 ... 9999).contains(value / 100) else {
                return value.string
            }
            return String(format: "%04ld-%02ld", value / 100, value % 100)
        default:
            return value.string
        }
    }
}
