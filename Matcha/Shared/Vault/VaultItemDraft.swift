import Foundation

/// An item being created or changed in the vault's window: the texts of its form, read from its content and written
/// back onto it, so that everything the form doesn't show (other credentials, unknown keys, history, files) stays
/// (`VAULT.md` § 9.3). Pure type.
nonisolated struct VaultItemDraft: Equatable, Sendable {
    /// The item; nil for a new one.
    var id: UUID?
    var category: VaultCategory
    var title = ""
    var favorite = false
    var tags: [String] = []
    var urls: [String] = []
    var match = VaultURLMatch.site
    var notes = ""
    /// The values of the category's fields (`VaultFieldSpec.id`).
    var values: [String: String] = [:]
    /// Custom fields: their entries, `label`, `type` and `value` edited in place.
    var fields: [VaultEntry] = []
    /// Files of the item (`VAULT.md` § 6), already sent.
    var files: [VaultEntry] = []
    /// For a document: passport, driving licence or identity document.
    var documentType = VaultCredentialType.identityDocument
    /// The content it was read from; nil for a new item.
    var original: VaultItemContent?

    init(category: VaultCategory) {
        self.category = category
    }

    init(id: UUID, content: VaultItemContent) {
        self.id = id
        original = content
        category = content.overview.category
        title = content.overview.title
        favorite = content.overview.favorite
        tags = content.overview.tags
        urls = content.overview.urls
        match = content.overview.match
        notes = content.details.notes
        fields = content.details.fields
        files = content.details.files
        if let type = VaultFieldSpec.documentTypes.first(where: { content.details.credential($0) != nil }) {
            documentType = type
        }
        for spec in specs {
            if spec.kind == .oneTimeCode, let totp = content.details.credential(VaultCredentialType.totp) {
                values[spec.id] = Self.oneTimeCodeText(totp)
            } else if let credential = content.details.credential(spec.credential) {
                values[spec.id] = credential.string(spec.key)
            }
        }
    }

    var specs: [VaultFieldSpec] {
        VaultFieldSpec.fields(of: category, document: documentType)
    }

    func value(_ spec: VaultFieldSpec) -> String {
        values[spec.id] ?? ""
    }

    /// The content to save: the original with this draft's values.
    func content() throws -> VaultItemContent {
        var content = original ?? VaultItemContent()
        content.overview.category = category
        content.overview.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.overview.favorite = favorite
        var seen: Set<String> = []
        content.overview.tags = tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        content.overview.urls = urls.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        content.overview.match = match
        content.details.notes = notes
        content.details.fields = fields.filter { !$0.string("label").isEmpty || !$0.string("value").isEmpty }
        content.details.files = files
        for spec in specs where spec.kind != .readOnly {
            try write(value(spec), for: spec, into: &content.details)
        }
        content.overview.subtitle = subtitle(of: content.details)
        return content
    }

    private func write(_ text: String, for spec: VaultFieldSpec, into details: inout VaultDetails) throws {
        guard spec.kind == .oneTimeCode else {
            if !text.isEmpty || details.credential(spec.credential) != nil {
                details.updateCredential(spec.credential) { $0.set(spec.key, text) }
            }
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            details.credentials.removeAll { $0.string("type") == VaultCredentialType.totp }
            return
        }
        let code = try Self.oneTimeCode(from: trimmed)
        details.updateCredential(VaultCredentialType.totp) { entry in
            entry.set("secret", Base32.encode(code.secret))
            entry.set("algorithm", code.algorithm.rawValue)
            entry.set("digits", integer: code.digits)
            entry.set("period", integer: code.period)
            entry.set("issuer", code.issuer ?? "")
        }
    }

    /// What the list shows under the title: never a secret (`VAULT.md` § 9.1).
    private func subtitle(of details: VaultDetails) -> String {
        switch category {
        case .login: details.credential(VaultCredentialType.basicAuth)?.string("username") ?? ""
        case .card: details.credential(VaultCredentialType.creditCard).map { "•••• " + String($0.string("number").suffix(4)) } ?? ""
        case .sshKey: details.credential(VaultCredentialType.sshKey)?.string("fingerprint") ?? ""
        case .identity: details.credential(VaultCredentialType.personName).map { "\($0.string("given")) \($0.string("surname"))" } ?? ""
        default: ""
        }
    }

    // MARK: One-time codes

    /// A one-time code from what was typed: an `otpauth://` address, or a base 32 secret with the usual settings.
    static func oneTimeCode(from text: String) throws -> OneTimeCode {
        if text.lowercased().hasPrefix("otpauth:"), let url = URL(string: text) {
            return try OneTimeCode(otpauth: url)
        }
        return try OneTimeCode(secret: Base32.decode(text), algorithm: .sha1, digits: 6, period: 30)
    }

    /// The code of a credential, as the form shows it: its address if it has non-default settings, else its secret.
    static func oneTimeCodeText(_ entry: VaultEntry) -> String {
        guard let code = oneTimeCode(of: entry) else {
            return entry.string("secret")
        }
        return code.algorithm == .sha1 && code.digits == 6 && code.period == 30 ? entry.string("secret") : code.uri
    }

    /// The code of a `totp` credential; nil if it isn't readable.
    static func oneTimeCode(of entry: VaultEntry) -> OneTimeCode? {
        guard let secret = try? Base32.decode(entry.string("secret")) else {
            return nil
        }
        let algorithm = OneTimeCode.Algorithm(rawValue: entry.string("algorithm")) ?? .sha1
        var code = try? OneTimeCode(
            secret: secret,
            algorithm: algorithm,
            digits: entry.integer("digits") ?? 6,
            period: entry.integer("period") ?? 30,
        )
        code?.issuer = entry.string("issuer").isEmpty ? nil : entry.string("issuer")
        return code
    }
}
