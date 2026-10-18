import Foundation

/// Listes de blocage livrées dans les ressources d'un paquet (tâche 6.2) : l'app, ou le paquet des tests pour leurs
/// listes d'essai. Xcode copie à plat les ressources du dossier synchronisé (`Resources/Blocklists/x.json` arrive dans
/// `Contents/Resources/x.json`) ; un sous-dossier `Blocklists` est aussi cherché, au cas où il serait gardé.
nonisolated struct BlocklistBundle: Sendable {
    enum Error: Swift.Error, Equatable {
        /// Le fichier d'une liste du manifeste manque dans les ressources.
        case missingFile(String)
    }

    static let subdirectory = "Blocklists"

    let bundle: Bundle
    var manifestName = BlocklistManifest.resourceName

    /// Manifeste des listes ; nil s'il n'y en a pas (aucune liste livrée : le bloqueur reste inactif).
    func manifest() async throws -> BlocklistManifest? {
        guard let url = url(of: manifestName) else {
            return nil
        }
        return try await BlocklistManifest(data: Self.read(url))
    }

    /// Règles de `entry` (JSON au format de WebKit), lues hors du fil principal.
    func rules(of entry: BlocklistEntry) async throws -> Data {
        guard let url = url(of: entry.file) else {
            throw Error.missingFile(entry.file)
        }
        return try await Self.read(url)
    }

    private func url(of name: String) -> URL? {
        bundle.url(forResource: name, withExtension: nil, subdirectory: Self.subdirectory)
            ?? bundle.url(forResource: name, withExtension: nil)
    }

    @concurrent
    private static func read(_ url: URL) async throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }
}
