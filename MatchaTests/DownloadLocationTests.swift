import Foundation
@testable import Matcha
import Testing

/// Dossier des téléchargements (tâche 5.1) : le vrai ~/Downloads, ou le sous-dossier des tests d'interface.
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

    /// Dans la sandbox (les tests tournent dans l'app), `FileManager` donne le dossier `Downloads` du conteneur, un
    /// lien vers le vrai ~/Downloads (droit « Downloads Folder ») : Matcha écrit dans le vrai dossier.
    @Test func `downloads go to the user's real Downloads folder`() throws {
        // Vrai dossier personnel : dans la sandbox, `NSHomeDirectory()` est le conteneur de l'app.
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
        // Sans sous-dossier valide, rien n'est effacé (et surtout pas Téléchargements).
        try DownloadLocation.resetTestSubfolderIfRequested(defaults: defaults([DownloadLocation.resetTestSubfolderKey: true]))
        try DownloadLocation.resetTestSubfolderIfRequested(defaults: defaults([
            DownloadLocation.resetTestSubfolderKey: true,
            DownloadLocation.testSubfolderKey: "Documents",
        ]))
        #expect(try FileManager.default.fileExists(atPath: #require(DownloadLocation.userDownloadsDirectory()).path))
    }

    /// Crée un vrai dossier dans ~/Downloads le temps du test.
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
