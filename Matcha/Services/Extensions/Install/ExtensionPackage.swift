import Foundation

/// Extension file chosen by the user (task 6.4): Chrome `.crx` (“Cr24” header version 2 or 3, followed by a zip
/// archive), Firefox `.xpi` or `.zip` (zip archives). The signature of a `.crx` is not verified: the user chooses the
/// file, and the permissions screen comes before any installation. Pure type.
nonisolated enum ExtensionPackage {
    enum Failure: Error, Equatable {
        /// Neither a `.crx` nor a zip archive.
        case unknownFormat
        /// Unreadable `.crx` header or unknown version.
        case invalidCRX
    }

    /// Zip archive contained in `data`: `data` itself for a zip archive, without its header for a `.crx`.
    static func zipData(from data: Data) throws -> Data {
        if starts(data, with: [0x50, 0x4B, 0x03, 0x04]) || starts(data, with: [0x50, 0x4B, 0x05, 0x06]) {
            return data
        }
        guard starts(data, with: Array("Cr24".utf8)) else {
            throw Failure.unknownFormat
        }
        guard let version = uint32(data, at: 4) else {
            throw Failure.invalidCRX
        }
        let archiveStart: Int
        switch version {
        case 2:
            // Public key and signature, of given lengths.
            guard let keyLength = uint32(data, at: 8), let signatureLength = uint32(data, at: 12) else {
                throw Failure.invalidCRX
            }
            archiveStart = 16 + Int(keyLength) + Int(signatureLength)
        case 3:
            // Header (protobuf) of given length.
            guard let headerLength = uint32(data, at: 8) else {
                throw Failure.invalidCRX
            }
            archiveStart = 12 + Int(headerLength)
        default:
            throw Failure.invalidCRX
        }
        guard archiveStart < data.count else {
            throw Failure.invalidCRX
        }
        // A slice: the archive isn't copied (review EX17).
        return data[(data.startIndex + archiveStart)...]
    }

    private static func starts(_ data: Data, with bytes: [UInt8]) -> Bool {
        data.count >= bytes.count && Array(data.prefix(bytes.count)) == bytes
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32? {
        LittleEndian.uint32(data, at: offset)
    }
}
