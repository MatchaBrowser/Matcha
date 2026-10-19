import Foundation
@testable import Matcha
import Testing

/// Unpacking an extension (audits E3 and E6): no links, within limits; the previous folder kept until the new one
/// loads.
struct ExtensionUnpackerTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ExtensionUnpackerTests-\(UUID().uuidString)")

    @Test func `a folder with a symbolic link is refused`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appending(path: "manifest.json"))
        try FileManager.default.createSymbolicLink(at: source.appending(path: "data.json"), withDestinationURL: URL(filePath: "/etc/hosts"))

        await #expect(throws: ExtensionUnpacker.Failure.link) {
            try await ExtensionUnpacker.unpack(source, into: root.appending(path: "staging"))
        }
        #expect(ExtensionInstallError(ExtensionUnpacker.Failure.link) == .containsLink)
    }

    @Test func `a folder without links is copied with its subfolders`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        try FileManager.default.createDirectory(at: source.appending(path: "icons"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appending(path: "manifest.json"))
        try Data("png".utf8).write(to: source.appending(path: "icons/16.png"))
        let staging = root.appending(path: "staging")

        #expect(try await ExtensionUnpacker.unpack(source, into: staging) == nil)
        #expect(try Data(contentsOf: staging.appending(path: "icons/16.png")) == Data("png".utf8))
    }

    @Test func `a file too large is refused before it is read`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let large = root.appending(path: "large.crx")
        #expect(FileManager.default.createFile(atPath: large.path, contents: nil))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(ExtensionUnpacker.maximumSize + 1))
        try handle.close()

        await #expect(throws: ExtensionUnpacker.Failure.tooLarge) {
            try await ExtensionUnpacker.unpack(large, into: root.appending(path: "staging"))
        }
    }

    @Test func `a folder swap keeps the previous folder until it is confirmed or undone`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "Extensions/ext")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("1".utf8).write(to: destination.appending(path: "version"))
        func newFolder(_ version: String) throws -> URL {
            let folder = root.appending(path: "new-\(version)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(version.utf8).write(to: folder.appending(path: "version"))
            return folder
        }

        let failed = try FolderSwap(placing: newFolder("2"), at: destination)
        #expect(try Data(contentsOf: destination.appending(path: "version")) == Data("2".utf8))
        failed.restore()
        #expect(try Data(contentsOf: destination.appending(path: "version")) == Data("1".utf8))

        let confirmed = try FolderSwap(placing: newFolder("3"), at: destination)
        confirmed.finish()
        #expect(try Data(contentsOf: destination.appending(path: "version")) == Data("3".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Extensions").path) == ["ext"])
    }
}
