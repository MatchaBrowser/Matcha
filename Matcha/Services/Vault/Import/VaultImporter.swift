import Foundation

/// Entry point of the import (`VAULT.md` § 10): reads the chosen file within a ceiling, recognizes its format by its
/// content, and hands it to the importer of that format. The file is never copied. Pure type, the reading of the file
/// aside.
nonisolated enum VaultImporter {
    /// The largest file of any format.
    static let maximumFileBytes = max(VaultExportFile.maximumBytes, VaultImportLimits.maximumArchiveBytes)

    /// The bytes of the file at `url`; `tooLarge` beyond `limit`, without reading further.
    static func contents(of url: URL, limit: Int = maximumFileBytes) throws -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw VaultImportError.unreadable
        }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: limit + 1) ?? Data()
        } catch {
            throw VaultImportError.unreadable
        }
        guard data.count <= limit else {
            throw VaultImportError.tooLarge
        }
        return data
    }

    /// The format of `data`, by its first bytes, its JSON keys or its CSV header; nil if it is none of them.
    static func format(of data: Data) -> VaultImportFormat? {
        if VaultExportFile.isFile(data) {
            return .matchaVault
        }
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return .onePassword
        }
        let text = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        if text.first(where: { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }) == UInt8(ascii: "{") {
            guard text.count <= VaultImportLimits.maximumCXFBytes, let json = try? VaultImportJSON(data: Data(text)) else {
                return nil
            }
            if VaultBitwardenImporter.isExport(json) {
                return .bitwarden
            }
            return VaultCXFReader.isDocument(json) ? .cxf : nil
        }
        // The header of a CSV: its first line.
        let line = data.prefix(4096).prefix { $0 != 0x0A && $0 != 0x0D }
        guard let header = try? VaultCSVParser.records(of: Data(line)).first, VaultCSVImporter.Columns(header: header) != nil else {
            return nil
        }
        return .csv
    }

    /// The drafts of a file of any format; `passwordRequired` for a `.matchavault` file without `password`.
    static func read(_ data: Data, password: String? = nil) throws -> VaultImportResult {
        switch format(of: data) {
        case .csv:
            return try VaultCSVImporter.read(data)
        case .bitwarden:
            return try VaultBitwardenImporter.read(data)
        case .onePassword:
            return try Vault1PUXImporter.read(data)
        case .cxf:
            return try VaultCXFReader.read(data)
        case .matchaVault:
            guard let password else {
                throw VaultImportError.passwordRequired
            }
            return try VaultCXFReader.read(VaultExportFile.open(data, password: password))
        case nil:
            throw VaultImportError.unknownFormat
        }
    }
}
