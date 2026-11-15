import Foundation

/// Why a file can't be imported at all.
nonisolated enum VaultImportError: Error, Equatable {
    /// Beyond the ceiling of its format (`VaultImportLimits`).
    case tooLarge
    /// Not text, JSON or an archive as its format requires, or of the wrong shape.
    case unreadable
    /// None of the formats Matcha imports.
    case unknownFormat
    /// An encrypted Bitwarden export: it must be exported again without encryption.
    case encryptedExport
    /// A newer version of the format (CXF, `.matchavault`).
    case unsupportedVersion
    /// A `.matchavault` file: its password is needed.
    case passwordRequired
    /// The password doesn't open the `.matchavault` file (or the file was modified).
    case wrongPassword
    /// Derivation parameters outside those Matcha accepts (`VAULT.md` § 10).
    case unsupportedKeyDerivation
}

/// Why an export can't be written.
nonisolated enum VaultExportError: Error, Equatable {
    /// Beyond what an import reads again (`VaultImportLimits.maximumCXFBytes`).
    case tooLarge
    /// An export password shorter than `SyncPassword.minimumLength` (`VAULT.md` § 10).
    case passwordTooShort
}
