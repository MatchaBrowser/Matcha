import Foundation

/// Reads CSV (RFC 4180): fields separated by commas, records by CRLF, LF or CR; a field in double quotes may hold
/// commas, line breaks and doubled quotes (`""`). A UTF-8 byte order mark is skipped, blank lines are left out. The
/// bytes are read as UTF-8, field by field (the separators are ASCII). Bounded: `VaultImportLimits.maximumRecords`
/// records of `maximumFieldsPerRecord` fields at most. Pure type.
nonisolated struct VaultCSVParser {
    private static let quote = UInt8(ascii: "\"")
    private static let comma = UInt8(ascii: ",")
    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    private var records: [[String]] = []
    private var record: [String] = []
    private var field: [UInt8] = []
    /// Inside a quoted field; and whether the current field was quoted (a quote after its end is a plain character).
    private var inQuotes = false
    private var wasQuoted = false

    /// The records of `data`; `VaultImportError.unreadable` for text that isn't UTF-8, a quote never closed or too many
    /// fields, `tooLarge` for too many records.
    static func records(of data: Data) throws -> [[String]] {
        var parser = VaultCSVParser()
        let bytes = [UInt8](data)
        var index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if parser.inQuotes {
                if byte == quote, index < bytes.count, bytes[index] == quote {
                    parser.field.append(quote)
                    index += 1
                } else if byte == quote {
                    parser.inQuotes = false
                } else {
                    parser.field.append(byte)
                }
                continue
            }
            try parser.read(byte)
            // CRLF: one line end.
            if byte == carriageReturn, index < bytes.count, bytes[index] == lineFeed {
                index += 1
            }
        }
        guard !parser.inQuotes else {
            throw VaultImportError.unreadable
        }
        if !parser.field.isEmpty || !parser.record.isEmpty || parser.wasQuoted {
            try parser.endRecord()
        }
        return parser.records
    }

    /// A byte outside quotes.
    private mutating func read(_ byte: UInt8) throws {
        switch byte {
        case Self.quote where field.isEmpty && !wasQuoted:
            inQuotes = true
            wasQuoted = true
        case Self.comma:
            try endField()
        case Self.lineFeed, Self.carriageReturn:
            try endRecord()
        default:
            field.append(byte)
        }
    }

    private mutating func endField() throws {
        guard let text = String(validating: field, as: UTF8.self), record.count < VaultImportLimits.maximumFieldsPerRecord else {
            throw VaultImportError.unreadable
        }
        record.append(text)
        field.removeAll(keepingCapacity: true)
        wasQuoted = false
    }

    private mutating func endRecord() throws {
        let isBlank = record.isEmpty && field.isEmpty && !wasQuoted
        try endField()
        if !isBlank {
            guard records.count < VaultImportLimits.maximumRecords else {
                throw VaultImportError.tooLarge
            }
            records.append(record)
        }
        record.removeAll()
    }
}
