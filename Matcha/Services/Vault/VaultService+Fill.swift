import Foundation
import OSLog

/// A login of the vault that matches a page (`VAULT.md` § 8.2).
nonisolated struct VaultFillCandidate: Identifiable, Equatable, Sendable {
    let item: VaultListItem
    /// `insecureMatch`: saved in `http`, filled on an `http` page with a warning.
    let result: VaultURLMatchResult

    var id: UUID {
        item.id
    }
}

/// What a login fills: its user name, its password, and its one-time code of now.
nonisolated struct VaultFillValues: Equatable, Sendable {
    let username: String
    let password: String
    let code: String?
}

/// What to offer after a login form was sent (`VAULT.md` § 8.4).
nonisolated enum VaultSaveDecision: Equatable, Sendable {
    /// Nothing: the vault has it already, or the user said never for this site.
    case none
    case save
    /// A login of the site with this user name and another password.
    case update(UUID)
}

/// The vault's filling (`VAULT.md` § 8): which logins match a page, their secrets, and saving what was sent.
extension VaultService {
    static let neverSaveKey = "vaultNeverSaveSites"

    /// The matcher, with the public suffix list read once.
    var urlMatcher: VaultURLMatcher? {
        if let matcher = loadedMatcher {
            return matcher
        }
        do {
            let matcher = try VaultURLMatcher(publicSuffixList: PublicSuffixList.bundled(in: .main))
            loadedMatcher = matcher
            return matcher
        } catch {
            Logger.vault.error("Public suffix list unreadable: \(error.logSummary, privacy: .public)")
            return nil
        }
    }

    /// The logins out of the trash that match `url` (a frame's origin, or the page's address), the most recently
    /// changed first.
    func logins(for url: URL) -> [VaultFillCandidate] {
        guard let matcher = urlMatcher else {
            return []
        }
        return items
            .filter { $0.overview.category == .login && !$0.overview.isTrashed && !$0.overview.urls.isEmpty }
            .compactMap { item in
                let result = matcher.match(itemURLs: item.overview.urls, rule: item.overview.match, page: url)
                return result.isMatch ? VaultFillCandidate(item: item, result: result) : nil
            }
            .sorted { ($0.item.overview.modifiedAt ?? .distantPast) > ($1.item.overview.modifiedAt ?? .distantPast) }
    }

    /// The user name, password and current one-time code of a login.
    func fillValues(of id: UUID, at date: Date = .now) throws -> VaultFillValues {
        let details = try content(of: id).details
        let login = details.credential(VaultCredentialType.basicAuth)
        let code = details.credential(VaultCredentialType.totp).flatMap(VaultItemDraft.oneTimeCode)?.code(at: date)
        return VaultFillValues(username: login?.string("username") ?? "", password: login?.string("password") ?? "", code: code)
    }

    // MARK: Saving

    /// Whether to offer saving a login sent on `url`.
    func saveDecision(username: String, password: String, url: URL) -> VaultSaveDecision {
        if let site = urlMatcher?.site(of: url), neverSaveSites.contains(site) {
            return .none
        }
        guard isUnlocked else {
            return .save
        }
        for candidate in logins(for: url) {
            guard let values = try? fillValues(of: candidate.id) else {
                continue
            }
            if values.username == username {
                return values.password == password ? .none : .update(candidate.id)
            }
        }
        return .save
    }

    /// Saves a sent login: a new item, or the new password of `id` (the old one goes into its history).
    @discardableResult
    func saveLogin(username: String, password: String, url: URL, updating id: UUID?) throws -> UUID {
        if let id {
            var content = try content(of: id)
            content.details.updateCredential(VaultCredentialType.basicAuth) { $0.set("password", password) }
            return try save(content, id: id)
        }
        var content = VaultItemContent()
        content.overview.category = .login
        content.overview.title = urlMatcher?.site(of: url) ?? url.host() ?? ""
        content.overview.subtitle = username
        content.overview.urls = [url.absoluteString]
        content.details.updateCredential(VaultCredentialType.basicAuth) { entry in
            entry.set("username", username)
            entry.set("password", password)
        }
        return try save(content)
    }

    var neverSaveSites: Set<String> {
        Set(defaults.stringArray(forKey: Self.neverSaveKey) ?? [])
    }

    /// “Never for this site”: kept on this Mac only.
    func neverSave(on url: URL) {
        guard let site = urlMatcher?.site(of: url) else {
            return
        }
        defaults.set(Array(neverSaveSites.union([site])).sorted(), forKey: Self.neverSaveKey)
    }
}
