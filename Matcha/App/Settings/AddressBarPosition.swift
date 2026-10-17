import Foundation

/// Emplacement de la barre d'adresse.
nonisolated enum AddressBarPosition: String, CaseIterable, Identifiable, Sendable {
    /// En haut de la barre latérale, comme dans Arc.
    case sidebar
    /// En haut de la carte de contenu, sur toute sa largeur, avec les boutons de navigation.
    case top

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .sidebar: "In the Sidebar"
        case .top: "Above the Page"
        }
    }
}
