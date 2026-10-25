import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// Hostile inputs of the extension formats (review TS9): protobuf and DER of a CRX header, ZIP archives, realistic CRX
/// files. Each file is built in the test.
struct ExtensionHostileFormatTests {
    // MARK: Protobuf

    @Test(arguments: [
        // Length of at least 2^63 (it trapped before review EX1).
        [0x12, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01],
        // Length beyond the message.
        [0x12, 0x05, 0x01],
        // Fixed 64-bit and 32-bit values cut short.
        [0x09, 0x01, 0x02, 0x03],
        [0x0D, 0x01, 0x02],
        // Varint missing, or longer than 10 bytes.
        [0x08],
        [0x08] + [UInt8](repeating: 0xFF, count: 11),
        // Groups (wire types 3 and 4) and unknown types.
        [0x0B],
        [0x0E],
    ] as [[UInt8]])
    func `hostile protobuf messages are refused`(bytes: [UInt8]) {
        #expect(ProtobufFields(bytes) == nil)
    }

    @Test func `the fields of a protobuf message are read, the others skipped`() throws {
        let message: [UInt8] = [0x08, 0x96, 0x01] + [0x12, 0x03, 0x61, 0x62, 0x63] + [0x09] + [UInt8](repeating: 7, count: 8)
            + [0x15, 1, 2, 3, 4] + [0x12, 0x00]
        let fields = try #require(ProtobufFields(message))
        #expect(fields.bytes(2) == [[0x61, 0x62, 0x63], []])
        #expect(fields.bytes(1).isEmpty)
    }

    // MARK: DER

    @Test func `a key's DER elements are read in short and long form`() throws {
        var short = DERReader(bytes: [0x04, 0x03, 1, 2, 3])
        #expect(short.element(tag: 0x04)?.bytes == [1, 2, 3])
        let long = [UInt8](repeating: 9, count: 200)
        var reader = DERReader(bytes: [0x04, 0x81, 200] + long)
        #expect(reader.element(tag: 0x04)?.bytes == long)
        let key = try #require(DERPublicKey.rsaKey(fromSubjectPublicKeyInfo: CRXBuilder.Developer().publicKeyInfo))
        #expect(!key.isEmpty)
    }

    @Test(arguments: [
        // Indefinite length (not DER), a length on 5 bytes, a length beyond the data, a wrong tag.
        [0x04, 0x80, 1, 2, 0, 0],
        [0x04, 0x85, 0, 0, 0, 0, 1, 1],
        [0x04, 0x82, 0xFF, 0xFF, 1],
        [0x04, 0x05, 1, 2],
        [0x02, 0x01, 1],
    ] as [[UInt8]])
    func `hostile DER elements are refused`(bytes: [UInt8]) {
        var reader = DERReader(bytes: bytes)
        #expect(reader.element(tag: 0x04) == nil)
    }

    @Test func `a public key with unused bits is refused`() {
        let info = CRXBuilder.der(0x30, CRXBuilder.der(0x30, Data()) + CRXBuilder.der(0x03, Data([0x01, 0xAA])))
        #expect(DERPublicKey.rsaKey(fromSubjectPublicKeyInfo: info) == nil)
    }

    // MARK: ZIP

    /// A one-file archive and the position of its central directory entry.
    private func archive() throws -> (data: Data, central: Int) {
        let data = try ZipWriter.archive([(path: "manifest.json", contents: Data("{}".utf8))])
        let central = try #require(data.firstRange(of: Data([0x50, 0x4B, 0x01, 0x02]))?.lowerBound)
        return (data, central - data.startIndex)
    }

    private func patched(_ data: Data, at offset: Int, _ value: UInt32) -> Data {
        var data = data
        data.replaceSubrange(offset ..< offset + 4, with: LittleEndian.bytes(value))
        return data
    }

    @Test func `encrypted, zip64 and oversized archives are refused`() throws {
        let (data, central) = try archive()
        var encrypted = data
        encrypted[central + 8] |= 0x01
        #expect(throws: ZipArchive.Failure.unsupported) { try ZipArchive(data: encrypted) }
        #expect(throws: ZipArchive.Failure.unsupported) { try ZipArchive(data: patched(data, at: central + 20, 0xFFFF_FFFF)) }
        let oversized = patched(data, at: central + 24, UInt32(ExtensionLimits.maximumUnpackedSize + 1))
        #expect(throws: ZipArchive.Failure.tooLarge) { try ZipArchive(data: oversized) }
    }

    /// Two entries over the same data (a “zip bomb” by overlap): each one is checked, and their declared sizes stay
    /// bounded together.
    @Test func `overlapping entries stay bounded and checked`() throws {
        let data = try ZipWriter.archive([(path: "a.js", contents: Data("x".utf8)), (path: "b.js", contents: Data("y".utf8))])
        let second = try #require(data.ranges(of: Data([0x50, 0x4B, 0x01, 0x02])).last?.lowerBound) - data.startIndex
        let overlapping = patched(data, at: second + 42, 0)
        let zip = try ZipArchive(data: overlapping)
        let entry = try #require(zip.entries.last)
        #expect(throws: ZipArchive.Failure.corrupted) { try zip.contents(of: entry) }
    }

    /// Review EX14: on APFS, a name that differs only by case or Unicode form would overwrite the other file.
    @Test(arguments: [
        ["manifest.json", "manifest.json"],
        ["manifest.json", "MANIFEST.JSON"],
        ["scripts/caf\u{E9}.js", "scripts/cafe\u{301}.js"],
        ["a/b.js", "a/./b.js"],
    ])
    func `two entries for one file are refused`(paths: [String]) throws {
        let archive = try ZipWriter.archive(paths.map { (path: $0, contents: Data("x".utf8)) })
        #expect(throws: ZipArchive.Failure.unsafePath(paths[1])) { try ZipArchive(data: archive) }
    }

    // MARK: CRX

    @Test func `the developer's proof names the publisher, first or not`() throws {
        let archive = try ZipWriter.archive([(path: "manifest.json", contents: Data("{}".utf8))])
        let developer = try CRXBuilder.Developer()
        let store = try CRXBuilder.Developer()
        let first = try CRXBuilder.crx(archive: archive, claimed: developer.publicKeyInfo, rsa: [(developer, false), (store, false)])
        #expect(CRXSignature.verifiedPublisher(of: first) == developer.identifier)
        let second = try CRXBuilder.crx(archive: archive, claimed: developer.publicKeyInfo, rsa: [(store, false), (developer, false)])
        #expect(CRXSignature.verifiedPublisher(of: second) == developer.identifier)
    }

    @Test func `a changed signature proves no publisher`() throws {
        let archive = try ZipWriter.archive([(path: "manifest.json", contents: Data("{}".utf8))])
        let developer = try CRXBuilder.Developer()
        let rsa = try CRXBuilder.crx(archive: archive, claimed: developer.publicKeyInfo, rsa: [(developer, true)])
        #expect(CRXSignature.verifiedPublisher(of: rsa) == nil)
        let key = P256.Signing.PrivateKey()
        let ecdsa = try CRXBuilder.crx(archive: archive, claimed: key.publicKey.derRepresentation, rsa: [], ecdsa: [(key, true)])
        #expect(CRXSignature.verifiedPublisher(of: ecdsa) == nil)
        let valid = try CRXBuilder.crx(archive: archive, claimed: key.publicKey.derRepresentation, rsa: [], ecdsa: [(key, false)])
        #expect(CRXSignature.verifiedPublisher(of: valid) != nil)
    }
}
