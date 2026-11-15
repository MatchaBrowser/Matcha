import Foundation

/// The issues of a login in the password check (`VAULT.md` § 9.7).
enum VaultSecurityText {
    static func summary(_ issues: Set<VaultSecurityReport.Issue>) -> String {
        [VaultSecurityReport.Issue.weak, .reused, .insecure].filter(issues.contains).map(name).joined(separator: ", ")
    }

    static func name(_ issue: VaultSecurityReport.Issue) -> String {
        switch issue {
        case .weak: String(localized: "Weak", comment: "Vault password check: a weak password")
        case .reused: String(localized: "Reused", comment: "Vault password check: a password used by several logins")
        case .insecure: String(localized: "Not secure (http)", comment: "Vault password check: a login for an http address")
        }
    }
}
