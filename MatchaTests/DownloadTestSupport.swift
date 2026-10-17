import Foundation
@testable import Matcha

/// Dossier temporaire propre à un test (dans le conteneur de l'app), effacé avec lui.
@MainActor
final class TemporaryDownloadsFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("MatchaDownloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Gestionnaire de téléchargements qui écrit dans ce dossier.
    func makeManager() -> DownloadManager {
        let url = url
        return DownloadManager(directory: { url })
    }

    /// Noms des fichiers du dossier, triés.
    func contents() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
