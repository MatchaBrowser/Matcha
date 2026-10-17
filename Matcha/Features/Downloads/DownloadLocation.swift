import Foundation
import OSLog

/// Dossier où vont les téléchargements : Téléchargements de l'utilisateur. Pour les tests d'interface, un sous-dossier
/// nommé par un argument de lancement, vidé au lancement si demandé : le lanceur des tests, sandboxé en lecture seule,
/// ne peut pas effacer ce que l'app y écrit.
nonisolated enum DownloadLocation {
    /// Argument de lancement : nom du sous-dossier de Téléchargements où écrire (tests d'interface).
    static let testSubfolderKey = "downloadsSubfolder"
    /// Argument de lancement : efface ce sous-dossier au lancement ; jamais Téléchargements lui-même.
    static let resetTestSubfolderKey = "resetDownloadsSubfolder"
    /// Seuls les noms qui commencent ainsi sont acceptés : un argument mal tapé ne vise jamais un dossier de
    /// l'utilisateur.
    static let testSubfolderPrefix = "MatchaUITests"

    /// Dossier Téléchargements de l'utilisateur. Dans la sandbox, `FileManager` donne le dossier `Downloads` du
    /// conteneur de l'app, un lien symbolique vers ~/Downloads (droit « Downloads Folder ») : il est résolu, pour que
    /// WebKit écrive et que le Finder montre le vrai dossier.
    static func userDownloadsDirectory() -> URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
    }

    /// Dossier des téléchargements de ce lancement.
    static func directory(defaults: UserDefaults = .standard) -> URL? {
        guard let downloads = userDownloadsDirectory() else {
            return nil
        }
        guard let name = testSubfolderName(defaults: defaults) else {
            return downloads
        }
        return downloads.appendingPathComponent(name, isDirectory: true)
    }

    /// Sous-dossier de test demandé au lancement, s'il est valide : un seul composant, préfixe `testSubfolderPrefix`.
    static func testSubfolderName(defaults: UserDefaults) -> String? {
        guard let name = defaults.string(forKey: testSubfolderKey), name.hasPrefix(testSubfolderPrefix),
              DownloadFileName.sanitized(name) == name
        else {
            return nil
        }
        return name
    }

    /// Au lancement de l'app : efface le sous-dossier de test si `resetDownloadsSubfolder` le demande.
    static func resetTestSubfolderIfRequested(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: resetTestSubfolderKey), let name = testSubfolderName(defaults: defaults),
              let downloads = userDownloadsDirectory()
        else {
            return
        }
        let folder = downloads.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: folder)
            Logger.downloads.info("Dossier des téléchargements de test effacé")
        } catch {
            Logger.downloads.error("Dossier des téléchargements de test non effacé : \(error.localizedDescription, privacy: .public)")
        }
    }
}
