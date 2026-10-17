import Foundation

/// Fichier de « Exporter en PDF… » (tâche 5.4), sans dépendance à l'interface : nom proposé et écriture.
nonisolated enum PDFExportFile {
    /// Nom de repli quand la page n'a ni titre ni hôte, jamais traduit : c'est un nom de fichier.
    static let fallbackName = "page"

    /// Nom proposé : le titre de la page rendu sûr (« / » devient « - », comme « : »), sinon l'hôte, sinon le nom du
    /// fichier local, sinon `fallbackName` ; « .pdf » ajouté s'il n'y est pas déjà, 255 octets au plus.
    static func name(title: String?, url: URL?) -> String {
        let candidates = [title, url?.host(percentEncoded: false), url.flatMap { $0.isFileURL ? $0.lastPathComponent : nil }]
        let base = candidates.lazy.compactMap { $0.map(baseName) }.first { !$0.isEmpty } ?? fallbackName
        return DownloadFileName.sanitized(base + ".pdf")
    }

    /// Écrit `data` d'un seul coup : dans un fichier temporaire du même volume, qui prend ensuite la place de
    /// `destination` (un fichier à moitié écrit ne remplace jamais l'ancien). Le dossier temporaire est celui que le
    /// système prévoit pour ces remplacements, permis dans la sandbox ; à défaut, celui de l'app.
    static func write(_ data: Data, to destination: URL, fileManager: FileManager = .default) throws {
        let replacementDirectory = try? fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true,
        )
        let temporary = (replacementDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        // Le dossier de remplacement est propre à cette écriture : il part avec le fichier temporaire.
        defer {
            try? fileManager.removeItem(at: replacementDirectory ?? temporary)
        }
        try data.write(to: temporary)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    /// Titre sans « / » ni « \ » (ils couperaient le nom), sans « .pdf » final ni espaces et points autour.
    private static func baseName(_ text: String) -> String {
        var name = DownloadFileName.sanitized(text.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-"))
        if name.lowercased().hasSuffix(".pdf") {
            name.removeLast(4)
        }
        return name.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
    }
}
