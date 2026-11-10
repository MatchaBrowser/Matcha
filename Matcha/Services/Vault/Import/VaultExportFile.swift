import CryptoKit
import Foundation

/// The encrypted export of the vault, a `.matchavault` file (`VAULT.md` § 10): the only file without the Secret Key,
/// so its password is derived slowly. Header = `MATCHAVAULT1` ‖ 16-byte salt ‖ iterations (4 bytes, big-endian); then
/// `0x01` ‖ AES-256-GCM (random 12-byte nonce, `SyncCrypto.seal`) of the CXF JSON padded to a multiple of 4 KiB, under
/// PBKDF2-SHA256(password in NFKD, salt, iterations), authenticating `matcha.vault.export.v1|` ‖ header. Written with
/// 1,000,000 iterations; read with 600,000 to 10,000,000 only (as `SYNC.md` § 3.1). Pure type.
nonisolated enum VaultExportFile {
    static let magic = Data("MATCHAVAULT1".utf8)
    static let saltLength = 16
    static let headerLength = 12 + 16 + 4
    static let writtenIterations = 1_000_000
    static let readIterations = 600_000 ... 10_000_000
    static let padding = 4096
    static let aadPrefix = Data("matcha.vault.export.v1|".utf8)
    /// The file: its content (`VaultImportLimits.maximumCXFBytes`), the padding, the header, nonce and tag.
    static let maximumBytes = VaultImportLimits.maximumCXFBytes + padding + headerLength + 1 + 12 + 16

    /// Whether `data` starts like a `.matchavault` file.
    static func isFile(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    /// The file of `contents` (the CXF JSON), under `password` (at least `SyncPassword.minimumLength` characters).
    static func seal(_ contents: Data, password: String) throws -> Data {
        try seal(contents, password: password, salt: SyncCrypto.randomBytes(saltLength), iterations: writtenIterations)
    }

    /// With a given salt, iteration count and nonce: the vectors and the quick tests only.
    static func seal(_ contents: Data, password: String, salt: Data, iterations: Int, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        guard SyncPassword.isLongEnough(password) else {
            throw VaultExportError.passwordTooShort
        }
        guard contents.count <= VaultImportLimits.maximumCXFBytes, salt.count == saltLength, let count = UInt32(exactly: iterations) else {
            throw VaultExportError.tooLarge
        }
        let header = magic + salt + withUnsafeBytes(of: count.bigEndian) { Data($0) }
        let key = try SymmetricKey(data: SyncCrypto.pbkdf2(password: SyncPassword.normalized(password), salt: salt, iterations: iterations))
        let sealed = try SyncCrypto.seal(SyncCrypto.pad(contents, toMultipleOf: padding), key: key, aad: aadPrefix + header, nonce: nonce)
        return header + Data([SyncCrypto.formatVersion]) + sealed
    }

    /// The CXF JSON of a file. `wrongPassword` if the password doesn't open it (or the file was modified),
    /// `unsupportedKeyDerivation` for an iteration count outside 600,000 … 10,000,000, checked before deriving.
    static func open(_ file: Data, password: String) throws -> Data {
        try open(file, password: password, iterations: readIterations)
    }

    /// With other accepted iteration counts: the quick tests only.
    static func open(_ file: Data, password: String, iterations accepted: ClosedRange<Int>) throws -> Data {
        guard file.count <= maximumBytes else {
            throw VaultImportError.tooLarge
        }
        let bytes = Data(file)
        guard isFile(bytes), bytes.count > headerLength + 1 else {
            throw VaultImportError.unreadable
        }
        let header = bytes.prefix(headerLength)
        let salt = header.subdata(in: magic.count ..< magic.count + saltLength)
        let iterations = Int(header.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        guard bytes[headerLength] == SyncCrypto.formatVersion else {
            throw VaultImportError.unsupportedVersion
        }
        guard accepted.contains(iterations) else {
            throw VaultImportError.unsupportedKeyDerivation
        }
        let key = try SymmetricKey(data: SyncCrypto.pbkdf2(password: SyncPassword.normalized(password), salt: salt, iterations: iterations))
        let padded: Data
        do {
            padded = try SyncCrypto.open(Data(bytes.suffix(from: headerLength + 1)), key: key, aad: aadPrefix + header)
        } catch {
            throw VaultImportError.wrongPassword
        }
        do {
            return try Data(SyncCrypto.unpad(padded))
        } catch {
            throw VaultImportError.unreadable
        }
    }
}
