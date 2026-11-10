import Foundation

/// Ceilings on what an import reads (`CLAUDE.md`, external data): the file is refused beyond them.
nonisolated enum VaultImportLimits {
    /// A CSV or JSON file, and the `export.data` of a 1PUX archive.
    static let maximumTextBytes = 20 * 1024 * 1024
    /// A 1PUX archive, attachments included.
    static let maximumArchiveBytes = 50 * 1024 * 1024
    /// A CXF document, ours included (`.matchavault`): what Matcha writes, it can read again.
    static let maximumCXFBytes = 64 * 1024 * 1024
    /// Records of a CSV, fields of a record.
    static let maximumRecords = 100_000
    static let maximumFieldsPerRecord = 256
    /// The overview of an item before padding (`VAULT.md` § 3.2).
    static let maximumOverviewBytes = 4 * 1024
}
