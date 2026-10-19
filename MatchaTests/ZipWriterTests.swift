import Foundation
@testable import Matcha
import Testing

/// Zip archive of an extension's folder (task 7.4), read back by `ZipArchive`.
struct ZipWriterTests {
    @Test func `a folder goes into an archive and comes back`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "zip-writer-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files: [String: Data] = [
            "manifest.json": Data(#"{"manifest_version":3,"name":"Essai","version":"1.0"}"#.utf8),
            "scripts/fond.js": Data(String(repeating: "console.log('matcha');\n", count: 200).utf8),
            "icônes/48.png": Data((0 ..< 2048).map { UInt8(truncatingIfNeeded: $0 &* 31) }),
            "vide.txt": Data(),
        ]
        for (path, contents) in files {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url)
        }
        try Data("caché".utf8).write(to: folder.appending(path: ".DS_Store"))

        let archive = try ZipArchive(data: ZipWriter.archive(folder: folder))
        #expect(archive.entries.map(\.path) == ["icônes/48.png", "manifest.json", "scripts/fond.js", "vide.txt"])
        for entry in archive.entries {
            #expect(try archive.contents(of: entry) == files[entry.path])
        }
        // The repeated script compresses, the image does not.
        #expect(archive.entries.first { $0.path == "scripts/fond.js" }?.method == 8)

        let extracted = folder.appending(path: "copie", directoryHint: .isDirectory)
        try archive.extract(to: extracted)
        #expect(try Data(contentsOf: extracted.appending(path: "scripts/fond.js")) == files["scripts/fond.js"])
    }
}

/// Audit E7: limits of an archive without zip64, and damaged entries, give errors, never a crash.
struct ZipLimitsTests {
    @Test func `too many entries or a too long name is refused`() {
        let entries = (0 ... ZipWriter.maximumEntries).map { (path: "f\($0)", contents: Data()) }
        #expect(throws: ZipWriter.Failure.tooLarge) {
            try ZipWriter.archive(entries)
        }
        #expect(throws: ZipWriter.Failure.tooLarge) {
            try ZipWriter.archive([(path: String(repeating: "a", count: Int(UInt16.max) + 1), contents: Data())])
        }
    }

    @Test func `an entry announced with content but without data is damaged`() throws {
        // One entry, “deflate”, 5 bytes announced, no compressed data.
        let name = Data("a.txt".utf8)
        func le16(_ value: Int) -> Data {
            withUnsafeBytes(of: UInt16(value).littleEndian) { Data($0) }
        }
        func le32(_ value: Int) -> Data {
            withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
        }
        var archive = Data()
        for field in [le32(0x0403_4B50), le16(20), le16(0), le16(8), le16(0), le16(0), le32(0), le32(0), le32(5)] {
            archive.append(field)
        }
        archive.append(le16(name.count) + le16(0) + name)
        var central = Data()
        for field in [le32(0x0201_4B50), le16(20), le16(20), le16(0), le16(8), le16(0), le16(0), le32(0), le32(0), le32(5)] {
            central.append(field)
        }
        for field in [le16(name.count), le16(0), le16(0), le16(0), le16(0), le32(0), le32(0), name] {
            central.append(field)
        }
        let offset = archive.count
        archive.append(central)
        for field in [le32(0x0605_4B50), le16(0), le16(0), le16(1), le16(1), le32(central.count), le32(offset), le16(0)] {
            archive.append(field)
        }

        let folder = FileManager.default.temporaryDirectory.appending(path: "ZipLimitsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: ZipArchive.Failure.corrupted) {
            try ZipArchive(data: archive).extract(to: folder)
        }
    }
}
