import Foundation

/// The formats an import reads (`VAULT.md` § 10).
nonisolated enum VaultImportFormat: Equatable, Sendable {
    /// Chrome, Safari or Firefox.
    case csv
    /// Unencrypted JSON export.
    case bitwarden
    /// 1PUX archive of 1Password.
    case onePassword
    case cxf
    /// Our encrypted export: its password is needed.
    case matchaVault
}
