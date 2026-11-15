import Foundation

/// Imports and exports of the vault (`VAULT.md` § 10): an import is one write, under a tag of its date; an export asks
/// for the master password, not Touch ID, then takes every item out of the trash.
extension VaultService {
    /// Saves imported items, each tagged `tag`; returns how many.
    func importItems(_ contents: [VaultItemContent], tag: String) throws -> Int {
        let tagged = contents.map { content in
            var content = content
            if !content.overview.tags.contains(tag) {
                content.overview.tags.append(tag)
            }
            if content.overview.title.trimmingCharacters(in: .whitespaces).isEmpty {
                content.overview.title = content.overview.subtitle
            }
            return content
        }
        return try saveAll(tagged)
    }

    /// Checks the master password against the envelope, as an unlock does: an export never trusts Touch ID alone.
    func checkPassword(_ password: String) async throws {
        guard let account, let envelope = try envelope(),
              let secretData = try account.keychain.data(for: .secretKey, server: account.server, accountID: account.accountID),
              let secretKey = SyncSecretKey(bytes: secretData)
        else {
            throw VaultError.unavailable
        }
        let keys = try await SyncService.derive {
            try SyncAccountKeys.passwordKeys(password: password, secretKey: secretKey, kdf: envelope.kdf)
        }
        guard (try? VaultCrypto.unwrapRootKey(envelope.wrappedVaultRootKey, with: keys.wrapKey)) != nil else {
            throw VaultError.wrongPassword
        }
    }

    /// The contents of every item out of the trash, for an export.
    func contentsForExport() throws -> [VaultItemContent] {
        try items.filter { !$0.overview.isTrashed }.map { try content(of: $0.id) }
    }

    /// The existing items' contents, to find the duplicates of an import.
    func existingContents() -> [VaultItemContent] {
        items.filter { !$0.overview.isTrashed }.compactMap { try? content(of: $0.id) }
    }
}
