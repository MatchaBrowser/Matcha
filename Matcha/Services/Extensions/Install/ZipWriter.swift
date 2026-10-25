import Compression
import Foundation

/// Writing of a zip archive (task 7.4): the folder of an installed extension, sent encrypted to your other Macs
/// (`SYNC.md` § 2.5). Each file is compressed with “deflate” if that makes it smaller, stored as is otherwise; the
/// entries follow the order of the paths; symbolic links and hidden system files (`.DS_Store`) are ignored. Read back
/// by `ZipArchive`. Pure type.
nonisolated enum ZipWriter {
    enum Failure: Error, Equatable {
        case unreadableFolder
        case tooLarge
    }

    /// Maximum size of a file, and of the archive (no zip64).
    static let maximumFileSize = Int(UInt32.max)
    /// Most entries: those an extension may have (`ExtensionLimits`, review EX23), below the 16-bit count of an
    /// archive without zip64 (audit E7).
    static let maximumEntries = ExtensionLimits.maximumEntries

    /// Archive of the content of `folder`, with paths relative to it; `tooLarge` beyond `limit` bytes, as soon as it is
    /// known (review SY16): a folder whose files weigh more than ten times the limit isn't even read.
    static func archive(folder: URL, limit: Int = maximumFileSize, fileManager: FileManager = .default) throws -> Data {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: Array(keys)) else {
            throw Failure.unreadableFolder
        }
        var files: [(path: String, url: URL)] = []
        var total = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true, url.lastPathComponent != ".DS_Store" else {
                continue
            }
            total += values.fileSize ?? 0
            guard total / 10 <= limit else {
                throw Failure.tooLarge
            }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base.path.count + 1)
            files.append((String(path), url))
        }
        return try archive(files.sorted { $0.path < $1.path }.map { file in try (file.path, Data(contentsOf: file.url)) }, limit: limit)
    }

    /// Archive of `entries` (relative path, content), in the given order; `tooLarge` as soon as it passes `limit`.
    static func archive(_ entries: [(path: String, contents: Data)], limit: Int = maximumFileSize) throws -> Data {
        guard entries.count <= maximumEntries else {
            throw Failure.tooLarge
        }
        var output = Data()
        var central = Data()
        for entry in entries {
            guard entry.contents.count < maximumFileSize, output.count < maximumFileSize - entry.contents.count else {
                throw Failure.tooLarge
            }
            let name = Data(entry.path.utf8)
            guard name.count <= Int(UInt16.max) else {
                throw Failure.tooLarge
            }
            let crc = CRC32.checksum(entry.contents)
            let deflated = deflate(entry.contents)
            let (method, stored): (UInt16, Data) = if let deflated, deflated.count < entry.contents.count {
                (8, deflated)
            } else {
                (0, entry.contents)
            }
            let offset = UInt32(output.count)
            // Local header: signature, version 2.0, UTF-8 flag, method, zero date.
            output.append(le32(0x0403_4B50))
            output.append(le16(20) + le16(0x0800) + le16(method) + le16(0) + le16(0x21))
            output.append(le32(crc) + le32(UInt32(stored.count)) + le32(UInt32(entry.contents.count)))
            output.append(le16(UInt16(name.count)) + le16(0))
            output.append(name)
            output.append(stored)
            guard output.count <= limit else {
                throw Failure.tooLarge
            }
            // Central directory entry.
            central.append(le32(0x0201_4B50))
            central.append(le16(0x031E) + le16(20) + le16(0x0800) + le16(method) + le16(0) + le16(0x21))
            central.append(le32(crc) + le32(UInt32(stored.count)) + le32(UInt32(entry.contents.count)))
            central.append(le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0))
            // External attributes: regular file, read and write (0644).
            central.append(le32(0o100644 << 16) + le32(offset))
            central.append(name)
        }
        guard output.count < maximumFileSize, central.count < maximumFileSize - output.count else {
            throw Failure.tooLarge
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count)))
        output.append(le32(UInt32(central.count)) + le32(centralOffset) + le16(0))
        return output
    }

    /// Raw “deflate” (RFC 1951), as in zip archives; nil if compression fails.
    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else {
            return nil
        }
        let capacity = data.count + data.count / 10 + 64
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let target = destination.bindMemory(to: UInt8.self).baseAddress,
                      let origin = source.bindMemory(to: UInt8.self).baseAddress
                else {
                    return 0
                }
                // `COMPRESSION_ZLIB` writes raw “deflate”, without a zlib header.
                return compression_encode_buffer(target, capacity, origin, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else {
            return nil
        }
        return output.prefix(written)
    }

    private static func le16(_ value: UInt16) -> Data {
        LittleEndian.bytes(value)
    }

    private static func le32(_ value: UInt32) -> Data {
        LittleEndian.bytes(value)
    }
}
