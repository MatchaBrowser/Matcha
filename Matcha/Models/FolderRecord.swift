import Foundation
import SwiftData

/// Dossier d'épinglés enregistré. Son ordre se range avec celui des onglets du même conteneur.
@Model
final class FolderRecord {
    var id = UUID()
    var name = ""
    var order = 0
    var isCollapsed = false
    var space: SpaceRecord?
    /// Dossier parent ; nil à la racine des épinglés.
    var parent: FolderRecord?
    @Relationship(deleteRule: .cascade, inverse: \FolderRecord.parent) var children: [FolderRecord]? = []
    @Relationship(deleteRule: .nullify, inverse: \TabRecord.folder) var tabs: [TabRecord]? = []

    init(id: UUID = UUID(), name: String, order: Int = 0, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.order = order
        self.isCollapsed = isCollapsed
    }
}
