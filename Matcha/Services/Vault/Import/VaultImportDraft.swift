import Foundation

/// An item being read from an imported file, and what of it could not be imported. Each credential and field gets its
/// own `id` (`VaultEntryID`). `finished()` checks it against the limits of an item and fills what the list shows.
/// Pure type.
nonisolated struct VaultImportDraft {
    var content = VaultItemContent()
    /// Parts of the entry left out.
    var issues: [VaultImportIssue.Reason] = []
    /// Set when the whole entry is left out.
    var skipReason: VaultImportIssue.Reason?
    let position: Int
    let sourceTitle: String

    init(position: Int, title: String, category: VaultCategory = .custom) {
        self.position = position
        sourceTitle = title
        content.overview.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.overview.category = category
    }

    var category: VaultCategory {
        get { content.overview.category }
        set { content.overview.category = newValue }
    }

    // MARK: Building

    /// Adds a credential of `type` with the values that aren't empty; nothing if all are. Returns its `id`.
    @discardableResult
    mutating func addCredential(_ type: String, _ values: [String: String]) -> String? {
        var entry = VaultEntry(["type": .string(type)])
        for (key, value) in values {
            entry.set(key, value)
        }
        return addCredential(entry)
    }

    /// Adds `entry` (its `type` set) under a new `id`, unless it holds nothing but its type.
    @discardableResult
    mutating func addCredential(_ entry: VaultEntry) -> String? {
        var entry = entry
        guard entry.keys.contains(where: { $0 != "type" && $0 != "id" }) else {
            return nil
        }
        entry.id = VaultEntryID.make()
        content.details.credentials.append(entry)
        return entry.id
    }

    /// Adds a custom field, unless its value is empty.
    mutating func addField(label: String, type: VaultFieldType, value: String) {
        guard !value.isEmpty else {
            return
        }
        var entry = VaultEntry(["label": .string(label), "type": .string(type.rawValue), "value": .string(value)])
        entry.id = VaultEntryID.make()
        content.details.fields.append(entry)
    }

    /// Appends a text to the notes, after a blank line if there are some.
    mutating func addNotes(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        content.details.notes = content.details.notes.isEmpty ? text : content.details.notes + "\n\n" + text
    }

    mutating func addURL(_ url: String) {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty, !content.overview.urls.contains(url) {
            content.overview.urls.append(url)
        }
    }

    mutating func addTag(_ tag: String) {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty, !content.overview.tags.contains(tag) {
            content.overview.tags.append(tag)
        }
    }

    /// Old passwords of the `basic-auth` credential `credentialID` (`VAULT.md` § 9.5), newest kept first.
    mutating func addPasswordHistory(_ passwords: [(value: String, date: Date)], credentialID: String) {
        for password in passwords where !password.value.isEmpty {
            let entry = VaultHistoryEntry(field: "\(credentialID).password", value: password.value, date: password.date, device: nil)
            content.addHistory(entry)
        }
    }

    // MARK: Finishing

    /// The draft as it goes into the result: the title taken from the host when there is none, the subtitle filled,
    /// and the entry skipped if it is empty or beyond the limits of an item (`VAULT.md` § 3.2).
    func finished() -> VaultImportDraft {
        var draft = self
        guard draft.skipReason == nil else {
            return draft
        }
        if draft.content.overview.title.isEmpty, let url = draft.content.overview.urls.first {
            draft.content.overview.title = Self.host(of: url)
        }
        draft.content.overview.subtitle = draft.subtitle
        draft.content.trimHistory()
        if draft.isEmpty {
            draft.skipReason = draft.issues.first ?? .empty
            draft.issues.removeFirst(min(1, draft.issues.count))
        } else if !draft.fitsLimits {
            draft.skipReason = .tooLarge
        }
        return draft
    }

    /// Nothing secret is left: empty, unless it is a title the user kept alone (an empty note) and nothing was dropped.
    private var isEmpty: Bool {
        let details = content.details
        let hasNothing = details.credentials.isEmpty && details.fields.isEmpty && details.notes.isEmpty
        return hasNothing && (content.overview.title.isEmpty || !issues.isEmpty)
    }

    private var fitsLimits: Bool {
        guard content.details.notes.utf8.count <= VaultDetails.maximumNotesBytes,
              let overview = try? content.encodedOverview(), overview.count <= VaultImportLimits.maximumOverviewBytes,
              let details = try? content.encodedDetails(), details.count <= VaultDetails.maximumBytes
        else {
            return false
        }
        return true
    }

    /// What the list shows under the title (`VAULT.md` § 9.1): the user name of a login, the last digits of a card, the
    /// fingerprint of an SSH key; never a secret.
    private var subtitle: String {
        let details = content.details
        switch category {
        case .login:
            return details.credential(VaultCredentialType.basicAuth)?.string("username") ?? ""
        case .card:
            let digits = (details.credential(VaultCredentialType.creditCard)?.string("number") ?? "").filter(\.isNumber)
            return digits.count >= 4 ? "•••• " + digits.suffix(4) : ""
        case .sshKey:
            return details.credential(VaultCredentialType.sshKey)?.string("fingerprint") ?? ""
        default:
            return content.overview.subtitle
        }
    }

    // MARK: Addresses

    /// The host of an address, in lowercase and without `www.`; an address without a scheme is read with `https://`
    /// (`VAULT.md` § 8.2). Empty if there is none.
    static func host(of url: String) -> String {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = URLComponents(string: text)?.host ?? URLComponents(string: "https://" + text)?.host ?? ""
        let lowercased = host.lowercased()
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }
}
