import Foundation

/// Arc's sidebar read from `StorableSidebar.json` (task 7.1): its Spaces, with their pinned and open tabs, and the
/// favorites of each profile. Pure type.
nonisolated struct ArcSidebar: Equatable, Sendable {
    /// Arc profile: the default one, or an added profile (name of its folder, like “Profile 1”).
    enum Profile: Hashable, Sendable {
        case `default`
        case custom(String)
    }

    /// Icon of an Arc Space: a name from its icon set (`skull`, `grid`…), or an emoji.
    enum Icon: Equatable, Sendable {
        case named(String)
        case emoji(String)
    }

    struct Space: Equatable, Sendable {
        var name: String
        var icon: Icon?
        /// Colors of the Arc theme (from 0 to 3, in order), without transparency.
        var colors: [ThemeColor]
        var profile: Profile
        /// Pinned tabs, folders included.
        var pinned: [ImportNode]
        /// Open tabs (not pinned).
        var openTabs: [ImportNode]
    }

    var spaces: [Space]
    /// Favorites (Arc's “Top Apps”) of each profile, in order.
    var favorites: [Profile: [ImportedTab]]
    /// Arc notes and items without a recognized address, left out.
    var skippedItems: Int
    /// Items beyond `ArcSidebarParser.maximumItems`, left out.
    var itemsBeyondLimit = 0

    var favoriteCount: Int {
        favorites.values.reduce(0) { $0 + $1.count }
    }

    /// Profiles added in Arc (other than the default one), in the order of their first appearance.
    var customProfiles: [String] {
        var names: [String] = []
        for profile in spaces.map(\.profile) {
            if case let .custom(name) = profile, !names.contains(name) {
                names.append(name)
            }
        }
        let favoriteOnly = favorites.keys.compactMap { profile -> String? in
            if case let .custom(name) = profile, !names.contains(name) {
                return name
            }
            return nil
        }
        return names + favoriteOnly.sorted()
    }
}
