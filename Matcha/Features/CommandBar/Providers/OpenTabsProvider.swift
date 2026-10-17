import Foundation

/// Onglets ouverts de tous les Spaces de la fenêtre, celui affiché d'abord. Le texte est ignoré :
/// le classement fait la correspondance.
///
/// Les favoris d'un profil sont communs à ses Spaces, mais chaque Space en garde sa propre copie
/// jusqu'à ce qu'on y passe (`adoptFavorites`) : ceux du profil affiché ne viennent que du Space
/// affiché, ceux d'un autre profil du premier de ses Spaces. Une fenêtre privée a sa propre session,
/// avec un seul Space : elle ne voit que ses onglets.
@MainActor
final class OpenTabsProvider: CommandProvider {
    private let windowModel: WindowModel

    init(windowModel: WindowModel) {
        self.windowModel = windowModel
    }

    func candidates(for _: CommandQuery, context _: CommandContext) async -> [CommandCandidate] {
        openTabs()
    }

    /// Favoris, épinglés (dossiers fermés compris) puis onglets du jour de chaque Space, sans l'onglet
    /// affiché, sans onglet vide et sans doublon d'identifiant.
    func openTabs() -> [CommandCandidate] {
        let current = windowModel.space
        let spaces = [current] + windowModel.session.spaces.filter { $0 !== current }
        var favoriteProfiles: Set<UUID?> = [current.record.profile?.id]
        var seen: Set<UUID> = []
        var result: [CommandCandidate] = []
        for space in spaces {
            let isCurrent = space === current
            let listsFavorites = isCurrent || favoriteProfiles.insert(space.record.profile?.id).inserted
            result += candidates(in: space, isCurrent: isCurrent, listsFavorites: listsFavorites, seen: &seen)
        }
        return result
    }

    private func candidates(
        in space: SpaceSession,
        isCurrent: Bool,
        listsFavorites: Bool,
        seen: inout Set<UUID>,
    ) -> [CommandCandidate] {
        let tabManager = space.tabManager
        var result: [CommandCandidate] = []
        for tab in tabManager.tabs {
            guard let place = tabManager.place(of: tab),
                  place != .favorite || listsFavorites,
                  !isCurrent || tab.id != tabManager.selectedTabID,
                  // Un épinglé déchargé montre son adresse d'origine.
                  let url = tab.url ?? tab.pinnedURL,
                  seen.insert(tab.id).inserted
            else {
                continue
            }
            let reference = TabReference(tabID: tab.id, spaceID: space.id)
            result.append(CommandCandidate(
                kind: .tab(reference, place: place, spaceName: isCurrent ? nil : space.record.name, lastActivity: tab.lastActivity),
                title: tab.displayTitle,
                url: url,
            ))
        }
        return result
    }
}
