import Compression
import Foundation

/// Écriture d'une archive zip (tâche 7.4) : le dossier d'une extension installée, envoyé chiffré à vos autres Mac
/// (`SYNC.md` § 2.5). Chaque fichier est compressé en « deflate » s'il y gagne, rangé tel quel sinon ; les entrées
/// suivent l'ordre des chemins ; les liens symboliques et les fichiers cachés du système (`.DS_Store`) sont ignorés.
/// Relue par `ZipArchive`. Type pur.
nonisolated enum ZipWriter {
    enum Failure: Error, Equatable {
        case unreadableFolder
        case tooLarge
    }

    /// Taille d'un fichier au plus (pas de zip64).
    static let maximumFileSize = Int(UInt32.max)

    /// Archive du contenu de `folder`, chemins relatifs à lui.
    static func archive(folder: URL, fileManager: FileManager = .default) throws -> Data {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw Failure.unreadableFolder
        }
        var files: [(path: String, url: URL)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, url.lastPathComponent != ".DS_Store" else {
                continue
            }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base.path.count + 1)
            files.append((String(path), url))
        }
        return try archive(files.sorted { $0.path < $1.path }.map { file in try (file.path, Data(contentsOf: file.url)) })
    }

    /// Archive de `entries` (chemin relatif, contenu), dans l'ordre donné.
    static func archive(_ entries: [(path: String, contents: Data)]) throws -> Data {
        var output = Data()
        var central = Data()
        for entry in entries {
            guard entry.contents.count < maximumFileSize, output.count < maximumFileSize else {
                throw Failure.tooLarge
            }
            let name = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.contents)
            let deflated = deflate(entry.contents)
            let (method, stored): (UInt16, Data) = if let deflated, deflated.count < entry.contents.count {
                (8, deflated)
            } else {
                (0, entry.contents)
            }
            let offset = UInt32(output.count)
            // En-tête local : signature, version 2.0, drapeau UTF-8, méthode, date nulle.
            output.append(le32(0x0403_4B50))
            output.append(le16(20) + le16(0x0800) + le16(method) + le16(0) + le16(0x21))
            output.append(le32(crc) + le32(UInt32(stored.count)) + le32(UInt32(entry.contents.count)))
            output.append(le16(UInt16(name.count)) + le16(0))
            output.append(name)
            output.append(stored)
            // Entrée du répertoire central.
            central.append(le32(0x0201_4B50))
            central.append(le16(0x031E) + le16(20) + le16(0x0800) + le16(method) + le16(0) + le16(0x21))
            central.append(le32(crc) + le32(UInt32(stored.count)) + le32(UInt32(entry.contents.count)))
            central.append(le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0))
            // Attributs externes : fichier ordinaire, lecture et écriture (0644).
            central.append(le32(0o100644 << 16) + le32(offset))
            central.append(name)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count)))
        output.append(le32(UInt32(central.count)) + le32(centralOffset) + le16(0))
        return output
    }

    /// « deflate » brut (RFC 1951), comme dans les archives zip ; nil si la compression échoue.
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
                // `COMPRESSION_ZLIB` écrit le « deflate » brut, sans en-tête zlib.
                return compression_encode_buffer(target, capacity, origin, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else {
            return nil
        }
        return output.prefix(written)
    }

    private static func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
