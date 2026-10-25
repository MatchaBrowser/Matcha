import Foundation

/// Tab manager referenced without being kept alive.
struct WeakTabManager {
    weak var manager: TabManager?
}

/// A profile's favorites, shared by its Spaces (`ProfileFavorites`, review ON1): the same tabs in each of them, saved
/// by one only; their links open in the Space of the window in front.
extension BrowserSession {
    /// The favorites of profile `profileID`, shared by its open Spaces.
    func favorites(of profileID: UUID?) -> ProfileFavorites {
        if let favorites = profileFavorites[profileID] {
            return favorites
        }
        let favorites = ProfileFavorites()
        profileFavorites[profileID] = favorites
        return favorites
    }

    /// Manager of a Space of profile `profileID`, which takes what is added to its favorites (import): any one, they
    /// share them; nil if the profile has no open Space.
    func favoritesManager(of profileID: UUID?) -> TabManager? {
        profileFavorites[profileID]?.saver
    }

    /// `space` is shown in the window in front: the links and windows opened by the favorites go to it.
    func showFavorites(in space: SpaceSession) {
        favorites(of: space.openedProfileID).focus(space.tabManager)
    }

    /// True if `space` saves its profile's favorites: the first open Space of the profile.
    func savesFavorites(_ space: SpaceSession) -> Bool {
        profileFavorites[space.openedProfileID]?.saver === space.tabManager
    }

    /// `space` is about to go away: if it saved the favorites, it saves them a last time (unless `saving` is false:
    /// they already are), and the next Space of the profile saves them from now on (`removeSpace`).
    func saveFavoritesBeforeLeaving(_ space: SpaceSession, saving: Bool = true) {
        if saving, savesFavorites(space) {
            space.saveNow()
        }
    }
}
