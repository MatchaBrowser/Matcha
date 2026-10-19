import Foundation
@testable import Matcha
import Testing

/// Downloads folder (task 5.1): the real ~/Downloads, or the UI tests' subfolder.
struct DownloadLocationTests {
    private func defaults(_ values: [String: Any]) throws -> UserDefaults {
        let name = "DownloadLocationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        return defaults
    }

    /// In the sandbox (the tests run in the app), `FileManager` gives the container's `Downloads` folder, a link to
    /// the real ~/Downloads (“Downloads Folder” entitlement): Matcha writes into the real folder.
    @Test func `downloads go to the user's real Downloads folder`() throws {
        // Real home folder: in the sandbox, `NSHomeDirectory()` is the app's container.
        let home = try String(cString: #require(getpwuid(getuid())).pointee.pw_dir)
        let directory = try #require(DownloadLocation.userDownloadsDirectory())
        #expect(directory.standardizedFileURL.path == URL(fileURLWithPath: home).appendingPathComponent("Downloads").standardizedFileURL
            .path)
        #expect(!directory.path.contains("/Library/Containers/"))
        #expect(try DownloadLocation.directory(defaults: defaults([:])) == directory)
    }

    @Test func `UI tests write in their own subfolder`() throws {
        let downloads = try #require(DownloadLocation.userDownloadsDirectory())
        let directory = try DownloadLocation.directory(defaults: defaults([DownloadLocation.testSubfolderKey: "MatchaUITests"]))
        #expect(directory == downloads.appendingPathComponent("MatchaUITests", isDirectory: true))
    }

    @Test(arguments: ["Documents", "", "MatchaUITests/../..", "../MatchaUITests", ".MatchaUITests", "MatchaUITests\n"])
    func `other subfolder names are ignored`(name: String) throws {
        #expect(try DownloadLocation.testSubfolderName(defaults: defaults([DownloadLocation.testSubfolderKey: name])) == nil)
        #expect(try DownloadLocation.directory(defaults: defaults([DownloadLocation.testSubfolderKey: name])) == DownloadLocation
            .userDownloadsDirectory())
    }

    @Test func `reset without a valid subfolder touches nothing`() throws {
        // Without a valid subfolder, nothing is deleted (and above all not Downloads).
        try DownloadLocation.resetTestSubfolderIfRequested(defaults: defaults([DownloadLocation.resetTestSubfolderKey: true]))
        try DownloadLocation.resetTestSubfolderIfRequested(defaults: defaults([
            DownloadLocation.resetTestSubfolderKey: true,
            DownloadLocation.testSubfolderKey: "Documents",
        ]))
        #expect(try FileManager.default.fileExists(atPath: #require(DownloadLocation.userDownloadsDirectory()).path))
    }

    /// Creates a real folder in ~/Downloads for the duration of the test.
    @Test func `reset removes the UI tests subfolder`() throws {
        let name = "MatchaUITests-\(UUID().uuidString)"
        let folder = try #require(DownloadLocation.userDownloadsDirectory()).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("abc".utf8).write(to: folder.appendingPathComponent("fichier.bin"))

        try DownloadLocation.resetTestSubfolderIfRequested(defaults: defaults([
            DownloadLocation.resetTestSubfolderKey: true,
            DownloadLocation.testSubfolderKey: name,
        ]))

        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
