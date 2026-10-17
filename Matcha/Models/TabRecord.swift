import Foundation
import SwiftData

/// Onglet enregistré. Un favori appartient au profil ; un épinglé ou un onglet du jour, au Space.
@Model
final class TabRecord {
    var id = UUID()
    var url: URL?
    var title: String?
    /// Place, en texte : `favorite`, `pinned`, `today`, ou `archived` (onglet archivé ; archivage reporté, voir `FEATURES.md`).
    var placeValue = TabPlace.today.rawValue
    /// Rang dans son conteneur (favoris, racine des épinglés, dossier, onglets du jour).
    var order = 0
    var lastActivity = Date.now
    /// Adresse et titre d'origine d'un épinglé ou d'un favori.
    var pinnedURL: URL?
    var pinnedTitle: String?
    /// État de navigation de WebKit (historique précédent/suivant), pour la restauration.
    @Attribute(.externalStorage) var interactionState: Data?
    /// Split view (tâche 4.3) dont l'onglet fait partie ; nil hors split. Jamais pour un favori.
    var splitGroupID: UUID?
    /// Part de largeur de son panneau dans le split ; 0 : inconnue (parts égales).
    var splitFraction = 0.0
    var space: SpaceRecord?
    var profile: ProfileRecord?
    var folder: FolderRecord?

    init(id: UUID = UUID(), url: URL? = nil, title: String? = nil, place: TabPlace = .today, order: Int = 0) {
        self.id = id
        self.url = url
        self.title = title
        placeValue = place.rawValue
        self.order = order
    }

    /// Place dans la barre ; nil pour un onglet archivé.
    var place: TabPlace? {
        get { TabPlace(rawValue: placeValue) }
        set { placeValue = newValue?.rawValue ?? "archived" }
    }
}
