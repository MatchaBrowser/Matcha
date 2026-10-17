import Foundation

/// Space où « Ouvrir dans le Space » envoie la page d'une mini-fenêtre, sans dépendance à l'interface.
nonisolated enum MiniWindowTarget {
    /// Ce que la règle sait d'un Space.
    struct Space: Equatable, Sendable {
        let id: UUID
        let profileID: UUID?
    }

    /// Space visé (bouton « Ouvrir dans … », ⌘O, ⌘-clic) pour une page du profil `profileID` :
    /// 1. le Space affiché par la fenêtre principale, s'il est de ce profil (le « plus récent » d'Arc) ;
    /// 2. sinon le premier Space de ce profil, dans l'ordre de la barre ;
    /// 3. sinon (plus aucun Space de ce profil) le Space affiché, puis le premier Space.
    /// Nil seulement sans aucun Space.
    static func defaultSpaceID(profileID: UUID?, displayedSpaceID: UUID?, spaces: [Space]) -> UUID? {
        let displayed = spaces.first { $0.id == displayedSpaceID }
        if let displayed, displayed.profileID == profileID {
            return displayed.id
        }
        if let sameProfile = spaces.first(where: { $0.profileID == profileID }) {
            return sameProfile.id
        }
        return displayed?.id ?? spaces.first?.id
    }
}
