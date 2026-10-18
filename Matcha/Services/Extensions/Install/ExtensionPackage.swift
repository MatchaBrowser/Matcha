import Foundation

/// Fichier d'extension choisi par l'utilisateur (tâche 6.4) : `.crx` de Chrome (en-tête « Cr24 » version 2 ou 3, suivi
/// d'une archive zip), `.xpi` de Firefox ou `.zip` (archives zip). La signature d'un `.crx` n'est pas vérifiée : c'est
/// l'utilisateur qui choisit le fichier, et l'écran des permissions passe avant toute installation. Type pur.
nonisolated enum ExtensionPackage {
    enum Failure: Error, Equatable {
        /// Ni un `.crx` ni une archive zip.
        case unknownFormat
        /// En-tête `.crx` illisible ou version inconnue.
        case invalidCRX
    }

    /// Archive zip contenue dans `data` : `data` lui-même pour une archive zip, sans son en-tête pour un `.crx`.
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
            // Clé publique et signature, de longueurs données.
            guard let keyLength = uint32(data, at: 8), let signatureLength = uint32(data, at: 12) else {
                throw Failure.invalidCRX
            }
            archiveStart = 16 + Int(keyLength) + Int(signatureLength)
        case 3:
            // En-tête (protobuf) de longueur donnée.
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
        return data.subdata(in: data.startIndex + archiveStart ..< data.endIndex)
    }

    private static func starts(_ data: Data, with bytes: [UInt8]) -> Bool {
        data.count >= bytes.count && Array(data.prefix(bytes.count)) == bytes
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else {
            return nil
        }
        let start = data.startIndex + offset
        return (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(data[start + $1]) << (8 * $1) }
    }
}
