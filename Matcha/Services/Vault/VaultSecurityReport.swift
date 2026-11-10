import Foundation

/// The analysis of the logins of the vault (`VAULT.md` § 9.7), made on this Mac while the vault is open, never sent:
/// weak passwords, passwords used by several logins, logins saved for `http`. Pure type.
nonisolated struct VaultSecurityReport: Equatable, Sendable {
    enum Issue: Hashable, Sendable {
        /// Under 50 bits by `SyncPasswordStrength`'s estimate.
        case weak
        /// The same password as another login.
        case reused
        /// An address in `http`: what is filled there can be read on the network.
        case insecure
    }

    /// A login and its password, as the analysis reads them.
    struct Login: Sendable {
        let id: UUID
        let password: String
        let urls: [String]
    }

    static let weakBits = 50.0

    private(set) var issues: [UUID: Set<Issue>] = [:]

    init(_ logins: [Login]) {
        var byPassword: [String: [UUID]] = [:]
        for login in logins where !login.password.isEmpty {
            byPassword[login.password, default: []].append(login.id)
            if SyncPasswordStrength.estimatedBits(of: login.password) < Self.weakBits {
                issues[login.id, default: []].insert(.weak)
            }
            if login.urls.contains(where: { $0.lowercased().hasPrefix("http:") }) {
                issues[login.id, default: []].insert(.insecure)
            }
        }
        for ids in byPassword.values where ids.count > 1 {
            for id in ids {
                issues[id, default: []].insert(.reused)
            }
        }
    }

    var count: Int {
        issues.count
    }
}

extension VaultService {
    /// The analysis of the logins out of the trash.
    func securityReport() -> VaultSecurityReport {
        let logins = items.filter { $0.overview.category == .login && !$0.overview.isTrashed }.compactMap { item in
            (try? fillValues(of: item.id)).map {
                VaultSecurityReport.Login(id: item.id, password: $0.password, urls: item.overview.urls)
            }
        }
        return VaultSecurityReport(logins)
    }
}
