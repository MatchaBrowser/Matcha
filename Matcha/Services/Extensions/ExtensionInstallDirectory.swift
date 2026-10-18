import Foundation

/// Dossier des extensions installées (tâche 6.3) : `Application Support/Extensions/<identifiant>/`, un dossier
/// décompressé par extension, avec son `manifest.json`. Le nom du dossier est l'identifiant de l'extension : il donne
/// son adresse (`webkit-extension://<identifiant>/`) et son stockage, qui doivent rester les mêmes d'un lancement à
/// l'autre. La tâche 6.4 y copiera les extensions installées. Type pur.
nonisolated enum ExtensionInstallDirectory {
    static let folderName = "Extensions"
    static let manifestName = "manifest.json"
    /// Longueur maximale d'un identifiant (une étiquette d'hôte).
    static let maximumIdentifierLength = 63

    /// Vrai si `identifier` peut servir d'identifiant : minuscules ASCII, chiffres et tirets, sans tiret au début ni à
    /// la fin, 63 caractères au plus (il devient l'hôte de l'adresse des pages de l'extension).
    static func isValidIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, identifier.count <= maximumIdentifierLength,
              identifier.first != "-", identifier.last != "-"
        else {
            return false
        }
        return identifier.unicodeScalars.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" }
    }

    /// Dossier des extensions dans `applicationSupport`.
    static func directory(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Extensions présentes dans `directory` : (identifiant, dossier), triées par identifiant. Un dossier au nom invalide
    /// ou sans `manifest.json`, un fichier ou un dossier caché est ignoré. Dossier absent : aucune.
    static func installedExtensions(in directory: URL, fileManager: FileManager = .default) -> [(identifier: String, url: URL)] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )) ?? []
        return contents
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDirectory && isValidIdentifier(url.lastPathComponent)
                    && fileManager.fileExists(atPath: url.appendingPathComponent(manifestName).path)
            }
            .map { (identifier: $0.lastPathComponent, url: $0) }
            .sorted { $0.identifier < $1.identifier }
    }
}
