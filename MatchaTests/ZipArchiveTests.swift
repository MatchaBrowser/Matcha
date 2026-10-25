import Foundation
@testable import Matcha
import Testing

/// Zip archives and extension packages (task 6.4): reading, dangerous paths, `.crx` header.
@MainActor
@Suite(.webKit)
struct ZipArchiveTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: TestPages.self).url(forResource: name, withExtension: nil))
        return try Data(contentsOf: url)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ZipArchiveTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func `a deflated archive extracts its files and folders`() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = try ZipArchive(data: fixture("test-extension-package.zip"))
        #expect(archive.entries.map(\.path).sorted() == [
            "TestExtension/manifest.json", "TestExtension/test-extension-background.js", "TestExtension/test-extension-content.js",
        ])
        try archive.extract(to: folder)
        let manifest = try Data(contentsOf: folder.appendingPathComponent("TestExtension/manifest.json"))
        #expect(try manifest == fixture("test-extension-manifest.json"))
    }

    @Test func `a stored archive extracts too`() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try ZipArchive(data: fixture("test-extension-package.xpi")).extract(to: folder)
        let content = try Data(contentsOf: folder.appendingPathComponent("test-extension-content.js"))
        #expect(try content == fixture("test-extension-content.js"))
    }

    @Test func `an entry leaving its folder is refused before anything is written`() throws {
        let parent = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let data = try fixture("test-zip-traversal.zip")
        #expect(throws: ZipArchive.Failure.unsafePath("../evil.txt")) {
            try ZipArchive(data: data).extract(to: parent.appendingPathComponent("inside"))
        }
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("evil.txt").path))
    }

    @Test func `unsafe paths`() throws {
        #expect(try ZipArchive.safeComponents(of: "a/./b/c.js") == ["a", "b", "c.js"])
        #expect(try ZipArchive.safeComponents(of: "dossier/") == ["dossier"])
        for path in ["/etc/passwd", "a/../../b", "..", "a\\b", "a\u{0}b"] {
            #expect(throws: ZipArchive.Failure.unsafePath(path)) { try ZipArchive.safeComponents(of: path) }
        }
    }

    @Test func `a damaged entry is detected by its checksum`() throws {
        var data = try fixture("test-extension-package.xpi")
        // First byte of the first file's content (stored as is): 30-byte local header plus its name.
        let nameLength = Int(data[26]) | Int(data[27]) << 8
        data[30 + nameLength] ^= 0xFF
        let archive = try ZipArchive(data: data)
        #expect(throws: ZipArchive.Failure.corrupted) { try archive.contents(of: archive.entries[0]) }
    }

    @Test func `not an archive`() {
        #expect(throws: ZipArchive.Failure.notAnArchive) { try ZipArchive(data: Data("pas une archive".utf8)) }
        #expect(throws: ZipArchive.Failure.notAnArchive) { try ZipArchive(data: Data()) }
    }

    @Test func `crc32 of a known text`() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    // MARK: Packages

    @Test func `a crx3 file holds a zip archive after its header`() throws {
        let zip = try ExtensionPackage.zipData(from: fixture("test-extension-package.crx"))
        #expect(zip.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(try ZipArchive(data: zip).entries.count == 3)
    }

    @Test func `a crx2 file skips its key and signature`() throws {
        let zip = try fixture("test-extension-package.xpi")
        var crx = Data("Cr24".utf8)
        for value: UInt32 in [2, 3, 2] {
            crx.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        }
        crx.append(contentsOf: [1, 2, 3, 4, 5])
        crx.append(zip)
        #expect(try ExtensionPackage.zipData(from: crx) == zip)
    }

    @Test func `zip and xpi files are kept as they are, other files refused`() throws {
        let xpi = try fixture("test-extension-package.xpi")
        #expect(try ExtensionPackage.zipData(from: xpi) == xpi)
        #expect(throws: ExtensionPackage.Failure.unknownFormat) { try ExtensionPackage.zipData(from: Data("{}".utf8)) }
        #expect(throws: ExtensionPackage.Failure.invalidCRX) { try ExtensionPackage.zipData(from: Data("Cr24".utf8)) }
        var unknownVersion = Data("Cr24".utf8)
        unknownVersion.append(contentsOf: [9, 0, 0, 0, 0, 0, 0, 0])
        #expect(throws: ExtensionPackage.Failure.invalidCRX) { try ExtensionPackage.zipData(from: unknownVersion) }
    }
}
