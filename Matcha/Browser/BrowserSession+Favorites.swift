import Foundation

/// Gestionnaire d'onglets retenu sans être gardé en vie.
struct WeakTabManager {
    weak var manager: TabManager?
}

/// Favoris d'un profil, communs à ses Spaces : un seul Space les tient à la fois (le dernier affiché, sinon le premier
/// du profil), et lui seul les enregistre. Les autres Spaces en gardent une copie, reprise du Space qui les tient quand
/// ils s'affichent (`adoptFavorites`) : sans ça, un Space resté en arrière-plan écraserait à son enregistrement les
/// favoris ajoutés ailleurs.
extension BrowserSession {
    /// Gestionnaire du Space qui tient les favoris du profil `profileID`.
    func favoritesHolder(of profileID: UUID?) -> TabManager? {
        if let profileID, let manager = favoritesHolders[profileID]?.manager, spaces.contains(where: { $0.tabManager === manager }) {
            return manager
        }
        return spaces.first { $0.record.profile?.id == profileID }?.tabManager
    }

    /// `space` s'affiche : il reprend les favoris de son profil (mêmes onglets, mêmes vues web ; leurs liens s'ouvrent
    /// désormais chez lui) et les tient.
    func showFavorites(in space: SpaceSession) {
        let profileID = space.record.profile?.id
        if let holder = favoritesHolder(of: profileID), holder !== space.tabManager {
            space.tabManager.adoptFavorites(from: holder)
        }
        if let profileID {
            favoritesHolders[profileID] = WeakTabManager(manager: space.tabManager)
        }
    }

    /// Vrai si `space` tient les favoris de son profil (et les enregistre).
    func holdsFavorites(_ space: SpaceSession) -> Bool {
        favoritesHolder(of: space.record.profile?.id) === space.tabManager
    }

    /// `space` va disparaître : s'il tenait les favoris, ils sont enregistrés et passent à un autre Space du profil.
    func handOverFavorites(from space: SpaceSession) {
        guard holdsFavorites(space) else {
            return
        }
        space.saveNow()
        let profileID = space.record.profile?.id
        guard let heir = spaces.first(where: { $0 !== space && $0.record.profile?.id == profileID }) else {
            return
        }
        heir.tabManager.adoptFavorites(from: space.tabManager)
        if let profileID {
            favoritesHolders[profileID] = WeakTabManager(manager: heir.tabManager)
        }
    }
}
