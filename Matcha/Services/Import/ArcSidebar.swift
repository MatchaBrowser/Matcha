import Foundation

/// Barre latérale d'Arc lue dans `StorableSidebar.json` (tâche 7.1) : ses Spaces, avec leurs épinglés et leurs
/// onglets ouverts, et les favoris de chaque profil. Type pur.
nonisolated struct ArcSidebar: Equatable, Sendable {
    /// Profil d'Arc : celui par défaut, ou un profil ajouté (nom de son dossier, comme « Profile 1 »).
    enum Profile: Hashable, Sendable {
        case `default`
        case custom(String)
    }

    /// Icône d'un Space d'Arc : un nom de son jeu d'icônes (`skull`, `grid`…), ou un emoji.
    enum Icon: Equatable, Sendable {
        case named(String)
        case emoji(String)
    }

    struct Space: Equatable, Sendable {
        var name: String
        var icon: Icon?
        /// Couleurs du thème d'Arc (de 0 à 3, dans l'ordre), sans transparence.
        var colors: [ThemeColor]
        var profile: Profile
        /// Épinglés, dossiers compris.
        var pinned: [ImportNode]
        /// Onglets ouverts (non épinglés).
        var openTabs: [ImportNode]
    }

    var spaces: [Space]
    /// Favoris (« Top Apps » d'Arc) de chaque profil, dans l'ordre.
    var favorites: [Profile: [ImportedTab]]
    /// Notes d'Arc et éléments sans adresse reconnue, laissés de côté.
    var skippedItems: Int

    var favoriteCount: Int {
        favorites.values.reduce(0) { $0 + $1.count }
    }

    /// Profils ajoutés dans Arc (autres que celui par défaut), dans l'ordre de leur première apparition.
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
