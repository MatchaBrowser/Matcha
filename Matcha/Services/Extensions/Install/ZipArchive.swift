import Compression
import Foundation

/// Lecture d'une archive zip (tâche 6.4) : `.zip`, `.xpi` de Firefox, ou contenu d'un `.crx` de Chrome
/// (`ExtensionPackage`). Seuls les fichiers rangés tels quels ou compressés en « deflate » sont pris ; une archive
/// chiffrée ou au format zip64 est refusée, comme toute entrée qui sortirait du dossier (chemin absolu, `..`) ; les
/// liens symboliques sont ignorés. Tailles bornées contre les archives démesurées. Type pur.
nonisolated struct ZipArchive {
    enum Failure: Error, Equatable {
        case notAnArchive
        case corrupted
        case unsupported
        case unsafePath(String)
        case tooLarge
    }

    struct Entry: Equatable {
        /// Chemin relatif, composants séparés par « / » ; finit par « / » pour un dossier.
        let path: String
        let method: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        let isSymbolicLink: Bool

        var isDirectory: Bool {
            path.hasSuffix("/")
        }
    }

    /// Taille totale décompressée au plus.
    static let maximumTotalSize = 512 * 1024 * 1024
    /// Nombre d'entrées au plus.
    static let maximumEntryCount = 20000

    let entries: [Entry]
    private let data: Data

    init(data: Data) throws {
        self.data = data
        entries = try Self.readCentralDirectory(of: data)
        guard entries.count <= Self.maximumEntryCount,
              entries.reduce(0, { $0 + $1.uncompressedSize }) <= Self.maximumTotalSize
        else {
            throw Failure.tooLarge
        }
        for entry in entries where !entry.isSymbolicLink {
            _ = try Self.safeComponents(of: entry.path)
        }
    }

    /// Contenu décompressé de `entry`, vérifié (taille, CRC-32).
    func contents(of entry: Entry) throws -> Data {
        let start = entry.localHeaderOffset
        guard try Self.uint32(data, at: start) == 0x0403_4B50 else {
            throw Failure.corrupted
        }
        let nameLength = try Int(Self.uint16(data, at: start + 26))
        let extraLength = try Int(Self.uint16(data, at: start + 28))
        let dataStart = start + 30 + nameLength + extraLength
        guard dataStart + entry.compressedSize <= data.count else {
            throw Failure.corrupted
        }
        let compressed = data.subdata(in: data.startIndex + dataStart ..< data.startIndex + dataStart + entry.compressedSize)
        let contents: Data
        switch entry.method {
        case 0:
            contents = compressed
        case 8:
            contents = try Self.inflate(compressed, size: entry.uncompressedSize)
        default:
            throw Failure.unsupported
        }
        guard contents.count == entry.uncompressedSize, CRC32.checksum(contents) == entry.crc32 else {
            throw Failure.corrupted
        }
        return contents
    }

    /// Écrit les fichiers et dossiers de l'archive dans `directory` (créé au besoin).
    func extract(to directory: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in entries where !entry.isSymbolicLink {
            let components = try Self.safeComponents(of: entry.path)
            guard !components.isEmpty else {
                continue
            }
            let url = components.reduce(directory) { $0.appendingPathComponent($1) }
            if entry.isDirectory {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents(of: entry).write(to: url)
            }
        }
    }

    /// Composants d'un chemin d'entrée ; refusé s'il est absolu, contient `..`, une barre oblique inverse ou un
    /// caractère nul.
    static func safeComponents(of path: String) throws -> [String] {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else {
            throw Failure.unsafePath(path)
        }
        let components = path.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !components.contains("..") else {
            throw Failure.unsafePath(path)
        }
        return components
    }

    // MARK: Lecture

    private static func readCentralDirectory(of data: Data) throws -> [Entry] {
        let end = try endOfCentralDirectory(in: data)
        let count = try Int(uint16(data, at: end + 10))
        let size = try Int(uint32(data, at: end + 12))
        let offset = try Int(uint32(data, at: end + 16))
        guard count != 0xFFFF, size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF else {
            throw Failure.unsupported
        }
        guard offset + size <= end else {
            throw Failure.corrupted
        }
        var entries: [Entry] = []
        var position = offset
        for _ in 0 ..< count {
            let (entry, next) = try readEntry(in: data, at: position)
            entries.append(entry)
            position = next
        }
        return entries
    }

    /// Entrée du répertoire central qui commence à `position`, et la position de la suivante.
    private static func readEntry(in data: Data, at position: Int) throws -> (Entry, next: Int) {
        guard try uint32(data, at: position) == 0x0201_4B50 else {
            throw Failure.corrupted
        }
        let madeBy = try uint16(data, at: position + 4)
        let flags = try uint16(data, at: position + 8)
        let compressedSize = try uint32(data, at: position + 20)
        let uncompressedSize = try uint32(data, at: position + 24)
        let nameLength = try Int(uint16(data, at: position + 28))
        let extraLength = try Int(uint16(data, at: position + 30))
        let commentLength = try Int(uint16(data, at: position + 32))
        let localOffset = try uint32(data, at: position + 42)
        guard flags & 0x1 == 0 else {
            throw Failure.unsupported
        }
        guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF else {
            throw Failure.unsupported
        }
        let nameStart = position + 46
        guard nameStart + nameLength <= data.count else {
            throw Failure.corrupted
        }
        let nameData = data.subdata(in: data.startIndex + nameStart ..< data.startIndex + nameStart + nameLength)
        // Bit 11 : nom en UTF-8 ; sinon, en pratique aussi de l'UTF-8 ou de l'ASCII.
        guard let path = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) else {
            throw Failure.corrupted
        }
        // Créée sous Unix (octet haut de « made by » = 3) : type de fichier dans les attributs externes.
        let mode = try uint32(data, at: position + 38) >> 16
        let entry = try Entry(
            path: path,
            method: uint16(data, at: position + 10),
            crc32: uint32(data, at: position + 16),
            compressedSize: Int(compressedSize),
            uncompressedSize: Int(uncompressedSize),
            localHeaderOffset: Int(localOffset),
            isSymbolicLink: madeBy >> 8 == 3 && mode & 0xF000 == 0xA000,
        )
        return (entry, nameStart + nameLength + extraLength + commentLength)
    }

    /// Position de la fin du répertoire central, cherchée depuis la fin (après un commentaire éventuel).
    private static func endOfCentralDirectory(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw Failure.notAnArchive
        }
        let lowest = max(0, data.count - 22 - 0xFFFF)
        var position = data.count - 22
        while position >= lowest {
            if try uint32(data, at: position) == 0x0605_4B50 {
                return position
            }
            position -= 1
        }
        throw Failure.notAnArchive
    }

    private static func inflate(_ compressed: Data, size: Int) throws -> Data {
        guard size > 0 else {
            return Data()
        }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                // `COMPRESSION_ZLIB` lit le « deflate » brut (RFC 1951) des archives zip.
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB,
                )
            }
        }
        guard written == size else {
            throw Failure.corrupted
        }
        return output
    }

    private static func uint16(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw Failure.corrupted
        }
        let start = data.startIndex + offset
        return UInt16(data[start]) | UInt16(data[start + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw Failure.corrupted
        }
        let start = data.startIndex + offset
        return (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(data[start + $1]) << (8 * $1) }
    }
}

/// Somme de contrôle CRC-32 des archives zip (polynôme 0xEDB88320). Type pur.
nonisolated enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { index in
        (0 ..< 8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { bytes in
            var crc = ~UInt32(0)
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
            return ~crc
        }
    }
}
