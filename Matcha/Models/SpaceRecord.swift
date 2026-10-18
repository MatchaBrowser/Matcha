import Foundation
import SwiftData

/// Space enregistré : ses onglets épinglés et du jour, ses dossiers, son thème.
@Model
final class SpaceRecord {
    var id = UUID()
    var name = ""
    /// Icône du Space (`SidebarIcon.spaceSymbol`) : nom d'un symbole SF, ou « emoji:<emoji> ».
    var symbol = "circle.fill"
    /// Thème encodé (`SpaceTheme`, tâche 3.4) ; nil pour le thème par défaut.
    var themeData: Data?
    var order = 0
    var profile: ProfileRecord?
    @Relationship(deleteRule: .cascade, inverse: \TabRecord.space) var tabs: [TabRecord]? = []
    @Relationship(deleteRule: .cascade, inverse: \FolderRecord.space) var folders: [FolderRecord]? = []

    init(id: UUID = UUID(), name: String, symbol: String = "circle.fill", order: Int = 0, profile: ProfileRecord? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.order = order
        self.profile = profile
    }

    /// Icône lue dans `symbol` (illisible : le cercle) ; l'écrire la remplace.
    var icon: SidebarIcon {
        get { SidebarIcon(spaceSymbol: symbol) }
        set { symbol = newValue.spaceSymbol }
    }
}
