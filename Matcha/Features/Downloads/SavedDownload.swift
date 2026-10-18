import Foundation
import OSLog

/// Un téléchargement tel que la liste le retient d'un lancement à l'autre : ceux des fenêtres ordinaires seulement,
/// jamais ceux des fenêtres privées. Ni l'adresse demandée ni la page d'origine. Type pur.
nonisolated struct SavedDownload: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case finished
        case failed
        case cancelled
        /// En cours quand l'app a été quittée (son fichier partiel est effacé).
        case interrupted
    }

    var id: UUID
    var fileName: String
    var fileURL: URL?
    var outcome: Outcome
    /// Taille du fichier écrit, ou part reçue.
    var byteCount: Int64
    /// Raison d'un échec, dans la langue de l'utilisateur au moment de l'échec.
    var failureReason: String?
}

/// Liste des téléchargements retenue dans les réglages de l'app (`downloadsList`, JSON), du plus récent au plus ancien,
/// jusqu'à ce que l'utilisateur l'efface (« Effacer »).
nonisolated enum SavedDownloadList {
    static let defaultsKey = "downloadsList"
    /// Les plus anciens au-delà ne sont plus retenus.
    static let limit = 100

    /// Liste retenue ; vide si rien n'est retenu ou si la valeur est illisible.
    static func load(from defaults: UserDefaults) -> [SavedDownload] {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([SavedDownload].self, from: data)
        } catch {
            Logger.downloads.error("Liste des téléchargements illisible : \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Retient `downloads` (les `limit` premiers) ; une liste vide efface la valeur.
    static func save(_ downloads: [SavedDownload], to defaults: UserDefaults) {
        guard !downloads.isEmpty else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        do {
            try defaults.set(JSONEncoder().encode(Array(downloads.prefix(limit))), forKey: defaultsKey)
        } catch {
            Logger.downloads.error("Liste des téléchargements non enregistrée : \(error.localizedDescription, privacy: .public)")
        }
    }
}
