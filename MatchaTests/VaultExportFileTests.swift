import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// The encrypted export `.matchavault` (`VAULT.md` § 10): a vector computed by another implementation (Python
/// `hashlib` and `cryptography`), bounds on the iterations, wrong password, tampering. PBKDF2 at 600,000 iterations and
/// more takes a fraction of a second: only two tests pay it, the others derive with 1,000.
struct VaultExportFileTests {
    private let password = "Café crème, 2026 !"
    private let salt = Data(0 ..< 16)
    private let contents = Data(#"{"hello":"world"}"#.utf8)

    private func sealed(iterations: Int = 1000) throws -> Data {
        let nonce = try AES.GCM.Nonce(data: Data(100 ..< 112))
        return try VaultExportFile.seal(contents, password: password, salt: salt, iterations: iterations, nonce: nonce)
    }

    private func hex(_ data: some Sequence<UInt8>) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    @Test func `the file matches the reference vector and opens with the public reader`() throws {
        let file = try sealed(iterations: 600_000)
        #expect(file.count == 4157)
        #expect(hex(file.prefix(32)) == "4d41544348415641554c5431000102030405060708090a0b0c0d0e0f000927c0")
        #expect(file[32] == 0x01)
        #expect(hex(file.suffix(16)) == "cde9f20469ebfbab4659a84d55e4fe79")
        #expect(hex(SHA256.hash(data: file)) == "d1902a52aaf4f56f5ba3a3a0aa2d58b4ba8bb9b32e75cc8e9000da145a669899")
        #expect(try VaultExportFile.open(file, password: password) == contents)
        // The password is normalized (NFKD): the composed and decomposed forms open the same file.
        #expect(try VaultExportFile.open(file, password: password.decomposedStringWithCanonicalMapping) == contents)
    }

    @Test func `a vault is exported with a million iterations and read back`() throws {
        let item = VaultItemContent(overview: VaultOverview(category: .note, title: "Alarm"), details: VaultDetails(notes: "4321"))
        let file = try VaultExportFile.seal(VaultCXFWriter.export([item]).data, password: password)
        #expect(file.prefix(12) == VaultExportFile.magic)
        #expect(hex(file[28 ..< 32]) == "000f4240")
        #expect((file.count - 32 - 1 - 12 - 16) % 4096 == 0)
        #expect(VaultImporter.format(of: file) == .matchaVault)
        #expect(throws: VaultImportError.passwordRequired) { try VaultImporter.read(file) }
        let result = try VaultImporter.read(file, password: password)
        #expect(result.items.map(\.overview.title) == ["Alarm"])
        #expect(result.items.first?.details.notes == "4321")
    }

    @Test func `a wrong password or a modified file doesn't open`() throws {
        let file = try sealed()
        let range = 1000 ... 1000
        #expect(try VaultExportFile.open(file, password: password, iterations: range) == contents)
        let unaccented = "Cafe creme, 2026 !"
        #expect(throws: VaultImportError.wrongPassword) { try VaultExportFile.open(file, password: unaccented, iterations: range) }
        for index in [14, 40, file.count - 1] {
            var modified = file
            modified[index] ^= 0x01
            #expect(throws: VaultImportError.wrongPassword) { try VaultExportFile.open(modified, password: password, iterations: range) }
        }
    }

    @Test func `iterations outside 600,000 to 10,000,000 are refused before deriving`() throws {
        // The count of a quick file, changed in its header: refused as it is read, whatever the rest.
        for iterations: UInt32 in [1000, 599_999, 10_000_001, .max] {
            var file = try sealed()
            file.replaceSubrange(28 ..< 32, with: withUnsafeBytes(of: iterations.bigEndian) { Data($0) })
            #expect(throws: VaultImportError.unsupportedKeyDerivation) { try VaultExportFile.open(file, password: password) }
        }
    }

    @Test func `other files, versions and sizes are refused`() throws {
        let other = Data("MATCHAVAULT2".utf8) + Data(count: 64)
        #expect(throws: VaultImportError.unreadable) { try VaultExportFile.open(other, password: password) }
        #expect(throws: VaultImportError.unreadable) { try VaultExportFile.open(VaultExportFile.magic, password: password) }
        var version = try sealed()
        version[32] = 0x02
        #expect(throws: VaultImportError.unsupportedVersion) { try VaultExportFile.open(version, password: password) }
        #expect(throws: VaultImportError.tooLarge) {
            try VaultExportFile.open(VaultExportFile.magic + Data(count: VaultExportFile.maximumBytes), password: password)
        }
        #expect(throws: VaultExportError.passwordTooShort) {
            try VaultExportFile.seal(contents, password: "short", salt: salt, iterations: 1000)
        }
    }
}
