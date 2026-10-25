import Foundation

/// Limits of an extension's files (audits E3 and E6, review EX23), the same for installing it and for its package sent
/// to your other Macs: what one Mac writes, another can read. Pure type.
nonisolated enum ExtensionLimits {
    /// A chosen file (`.crx`, `.xpi`, `.zip`).
    static let maximumFileSize = 256 * 1024 * 1024
    /// Everything unpacked: an archive's content, or a chosen folder.
    static let maximumUnpackedSize = 512 * 1024 * 1024
    /// Files and folders of an extension.
    static let maximumEntries = 20000
}
