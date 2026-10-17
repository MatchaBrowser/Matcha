import Foundation
import SwiftData

/// Visite d'une page (tâche 5.5) : une page principale chargée, ou une adresse changée par la page elle-même
/// (`HistoryRecordingPolicy`). Jamais pour une fenêtre privée. Reste sur le Mac (`SYNC.md`), gardée un an.
@Model
final class HistoryRecord {
    var id = UUID()
    /// Adresse sans fragment ni identifiants (`HistoryRecordingPolicy.storedURL`).
    var url: URL?
    /// Clé de l'adresse (`CommandText.urlKey`), calculée une fois à l'écriture : les visites d'une même page se
    /// regroupent sans relire chaque adresse au chargement de l'historique.
    var urlKey = ""
    var title: String?
    var visitDate = Date.now
    /// Profil de la page (pas de relation : supprimé explicitement avec le profil, comme `SitePermissionRecord`).
    var profileID: UUID?
    /// Space de l'onglet ou de l'aperçu ; nil pour une mini-fenêtre.
    var spaceID: UUID?

    init(id: UUID = UUID(), url: URL, urlKey: String, title: String?, visitDate: Date, profileID: UUID?, spaceID: UUID?) {
        self.id = id
        self.url = url
        self.urlKey = urlKey
        self.title = title
        self.visitDate = visitDate
        self.profileID = profileID
        self.spaceID = spaceID
    }
}
