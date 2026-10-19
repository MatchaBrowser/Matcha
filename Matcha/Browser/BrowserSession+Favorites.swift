import Foundation

/// Tab manager referenced without being kept alive.
struct WeakTabManager {
    weak var manager: TabManager?
}

/// A profile's favorites, shared by its Spaces (profile at opening: `openedProfileID`): only one Space holds them at a
/// time (the last one shown, otherwise the profile's first), and only that Space saves them. The other Spaces keep a
/// copy, taken from the holding Space when they are shown (`adoptFavorites`): without this, a Space left in the
/// background would overwrite, when it saves, the favorites added elsewhere.
extension BrowserSession {
    /// Manager of the Space that holds the favorites of profile `profileID`.
    func favoritesHolder(of profileID: UUID?) -> TabManager? {
        if let profileID, let manager = favoritesHolders[profileID]?.manager, spaces.contains(where: { $0.tabManager === manager }) {
            return manager
        }
        return spaces.first { $0.openedProfileID == profileID }?.tabManager
    }

    /// `space` is shown: it takes over its profile's favorites (same tabs, same web views; their links now open in it)
    /// and holds them.
    func showFavorites(in space: SpaceSession) {
        let profileID = space.openedProfileID
        if let holder = favoritesHolder(of: profileID), holder !== space.tabManager {
            space.tabManager.adoptFavorites(from: holder)
        }
        if let profileID {
            favoritesHolders[profileID] = WeakTabManager(manager: space.tabManager)
        }
    }

    /// True if `space` holds its profile's favorites (and saves them).
    func holdsFavorites(_ space: SpaceSession) -> Bool {
        favoritesHolder(of: space.openedProfileID) === space.tabManager
    }

    /// `space` is about to go away: if it held the favorites, they are saved (unless `saving` is false: they already
    /// are) and pass to another Space of the profile.
    func handOverFavorites(from space: SpaceSession, saving: Bool = true) {
        guard holdsFavorites(space) else {
            return
        }
        if saving {
            space.saveNow()
        }
        let profileID = space.openedProfileID
        guard let heir = spaces.first(where: { $0 !== space && $0.openedProfileID == profileID }) else {
            return
        }
        heir.tabManager.adoptFavorites(from: space.tabManager)
        if let profileID {
            favoritesHolders[profileID] = WeakTabManager(manager: heir.tabManager)
        }
    }
}
