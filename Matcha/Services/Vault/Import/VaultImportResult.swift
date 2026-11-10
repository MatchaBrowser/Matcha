import Foundation

/// What an import read from a file (`VAULT.md` § 10): the drafts of its items, and what could not be imported. The
/// drafts are not dated (`modifiedAt` and `modifiedBy` are nil, the caller dates them when it writes them), and their
/// title may be empty (the caller names them). Pure type.
nonisolated struct VaultImportResult: Equatable, Sendable {
    var items: [VaultItemContent] = []
    var issues: [VaultImportIssue] = []

    /// Entries of the file left out entirely.
    var skippedCount: Int {
        issues.count(where: \.isItemSkipped)
    }

    /// Adds the item of `draft` if it can be imported, and its issues.
    mutating func add(_ draft: VaultImportDraft) {
        let finished = draft.finished()
        for reason in finished.issues {
            issues.append(VaultImportIssue(position: draft.position, title: draft.sourceTitle, reason: reason, isItemSkipped: false))
        }
        if let reason = finished.skipReason {
            issues.append(VaultImportIssue(position: draft.position, title: draft.sourceTitle, reason: reason, isItemSkipped: true))
        } else {
            items.append(finished.content)
        }
    }
}

/// Something of the file that could not be imported: a whole entry, or a part of an imported item (a linked field, an
/// attachment, a passkey). The reason is an enum: the interface words it.
nonisolated struct VaultImportIssue: Equatable, Hashable, Sendable {
    nonisolated enum Reason: Equatable, Hashable, Sendable {
        /// Nothing to import: neither a user name, a password, a note, a field nor a credential.
        case empty
        /// Beyond the limits of an item (`VAULT.md` § 3.2): 64 KiB of notes, 96 KiB of details, 4 KiB of overview.
        case tooLarge
        /// A kind of entry or of credential this version doesn't import, as the file names it: a Bitwarden type
        /// number, a 1Password category, a CXF credential type.
        case unsupportedType(String)
        /// An attachment or a document: files are not imported.
        case attachment
        /// A passkey: not imported.
        case passkey
        /// A Bitwarden linked field: it points at another field of the item.
        case linkedField
        /// A one-time code whose setup is unreadable, or outside what Matcha computes (`VAULT.md` § 9.7).
        case invalidOneTimeCode
        /// An SSH key this version can't turn into the OpenSSH format: kept as it came.
        case unconvertedSSHKey
        /// A field of a kind this version doesn't import, as the file names it.
        case unsupportedField(String)
        /// An entry of the wrong shape.
        case unreadable
    }

    /// Position of the entry in the file, from 1: its record after the header in a CSV, its place among all the items
    /// otherwise.
    let position: Int
    /// Its title in the file, possibly empty: data, not a text of the interface.
    let title: String
    let reason: Reason
    /// The whole entry was left out; otherwise only this part of an imported item.
    let isItemSkipped: Bool
}
