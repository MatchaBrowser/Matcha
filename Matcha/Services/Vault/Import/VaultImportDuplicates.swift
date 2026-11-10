import Foundation

/// Finds the imported drafts that are already in the vault (`VAULT.md` § 10): the same site (the host of the first
/// address, without `www.`), the same user name and the same password. Only logins are compared, items in the trash
/// don't count, and a draft that repeats an earlier one of the same file is a duplicate too. Pure type.
nonisolated enum VaultImportDuplicates {
    struct Key: Hashable {
        let site: String
        let username: String
        let password: String
    }

    /// What two logins must share; nil for an item without a user name or a password.
    static func key(of item: VaultItemContent) -> Key? {
        guard let login = item.details.credential(VaultCredentialType.basicAuth),
              !login.string("username").isEmpty || !login.string("password").isEmpty
        else {
            return nil
        }
        let site = VaultImportDraft.host(of: item.overview.urls.first ?? "")
        return Key(site: site, username: login.string("username"), password: login.string("password"))
    }

    /// The positions in `drafts` of those that repeat an item of `existing`, or an earlier draft.
    static func duplicates(in drafts: [VaultItemContent], existing: [VaultItemContent]) -> IndexSet {
        var seen = Set(existing.filter { !$0.overview.isTrashed }.compactMap(key))
        var duplicates = IndexSet()
        for (index, draft) in drafts.enumerated() {
            if let key = key(of: draft), !seen.insert(key).inserted {
                duplicates.insert(index)
            }
        }
        return duplicates
    }
}
