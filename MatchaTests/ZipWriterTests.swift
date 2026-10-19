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
