import Foundation

/// Imports a 1Password export (1PUX, `VAULT.md` § 10): a zip archive whose `export.data` holds the accounts, their
/// vaults and their items in JSON; the attachments beside it are not read. The archive is read by `ZipArchive` (that of
/// the extensions), within `VaultImportLimits`: 50 MB for the archive, 20 MB for `export.data`. Each item is read by
/// `Vault1PUXItem`. Pure type.
nonisolated enum Vault1PUXImporter {
    static let dataPath = "export.data"

    /// The items of every vault of every account of the archive.
    static func read(_ data: Data) throws -> VaultImportResult {
        guard data.count <= VaultImportLimits.maximumArchiveBytes else {
            throw VaultImportError.tooLarge
        }
        let json = try VaultImportJSON(data: exportData(of: data))
        guard json["accounts"].isArray else {
            throw VaultImportError.unreadable
        }
        var result = VaultImportResult()
        var position = 0
        for account in json["accounts"].array {
            for vault in account["vaults"].array {
                for item in vault["items"].array {
                    position += 1
                    result.add(Vault1PUXItem(item, position: position).draft)
                }
            }
        }
        return result
    }

    /// The content of `export.data`, unpacked only once its announced size is within the ceiling.
    static func exportData(of archive: Data) throws -> Data {
        let zip: ZipArchive
        do {
            zip = try ZipArchive(data: archive)
        } catch ZipArchive.Failure.tooLarge {
            throw VaultImportError.tooLarge
        } catch {
            throw VaultImportError.unreadable
        }
        guard let entry = zip.entries.first(where: { $0.path == dataPath && !$0.isSymbolicLink }) else {
            throw VaultImportError.unknownFormat
        }
        guard entry.uncompressedSize <= VaultImportLimits.maximumTextBytes else {
            throw VaultImportError.tooLarge
        }
        do {
            return try zip.contents(of: entry)
        } catch {
            throw VaultImportError.unreadable
        }
    }
}
