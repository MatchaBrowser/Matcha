import Foundation

/// Imports the passwords exported as CSV (`VAULT.md` § 10) by Chrome (`name,url,username,password,note`), Safari
/// (`Title,URL,Username,Password,Notes,OTPAuth`) and Firefox (`url,username,password,httpRealm,formActionOrigin,guid,
/// timeCreated,timeLastUsed,timePasswordChanged`). The columns are found by their names in the header (case and order
/// ignored), and a missing column reads as empty. Each record is a login: a `basic-auth` credential, its address, the
/// one-time code of Safari (`OTPAuth`), the notes, and the creation date of Firefox. Pure type.
nonisolated enum VaultCSVImporter {
    /// Where each value is in a record.
    struct Columns: Equatable {
        var title: Int?
        var url: Int
        var username: Int
        var password: Int
        var notes: Int?
        var otpAuth: Int?
        /// Firefox: milliseconds since 1970.
        var timeCreated: Int?

        /// The columns of `header`; nil without `url`, `username` and `password`.
        init?(header: [String]) {
            let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let column = { (candidates: [String]) in candidates.lazy.compactMap { names.firstIndex(of: $0) }.first }
            guard let url = column(["url"]), let username = column(["username"]), let password = column(["password"]) else {
                return nil
            }
            self.url = url
            self.username = username
            self.password = password
            title = column(["title", "name"])
            notes = column(["notes", "note"])
            otpAuth = column(["otpauth"])
            timeCreated = column(["timecreated"])
        }
    }

    /// The logins of a CSV file; `unknownFormat` if its header is none of those above.
    static func read(_ data: Data) throws -> VaultImportResult {
        guard data.count <= VaultImportLimits.maximumTextBytes else {
            throw VaultImportError.tooLarge
        }
        let records = try VaultCSVParser.records(of: data)
        guard let header = records.first, let columns = Columns(header: header) else {
            throw VaultImportError.unknownFormat
        }
        var result = VaultImportResult()
        for (index, record) in records.dropFirst().enumerated() where record.contains(where: { !$0.isEmpty }) {
            result.add(draft(of: record, columns: columns, position: index + 1))
        }
        return result
    }

    /// The login of one record.
    static func draft(of record: [String], columns: Columns, position: Int) -> VaultImportDraft {
        let value = { (column: Int?) -> String in
            guard let column, column < record.count else {
                return ""
            }
            return record[column]
        }
        var draft = VaultImportDraft(position: position, title: value(columns.title), category: .login)
        let username = value(columns.username)
        let password = value(columns.password)
        let otpAuth = value(columns.otpAuth).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty || !password.isEmpty || !otpAuth.isEmpty || !value(columns.notes).isEmpty else {
            draft.skipReason = .empty
            return draft
        }
        draft.addURL(value(columns.url))
        draft.addCredential(VaultCredentialType.basicAuth, ["username": username, "password": password])
        if !otpAuth.isEmpty {
            if let totp = VaultOTPAuth.credential(from: otpAuth) {
                draft.addCredential(totp)
            } else {
                draft.issues.append(.invalidOneTimeCode)
            }
        }
        draft.addNotes(value(columns.notes))
        if let milliseconds = Double(value(columns.timeCreated)) {
            draft.content.details.createdAt = VaultImportJSON.date(milliseconds, scale: 1000)
        }
        return draft
    }
}
