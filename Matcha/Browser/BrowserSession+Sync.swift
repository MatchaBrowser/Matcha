import Foundation
import SwiftData

/// Session après des changements reçus d'un autre Mac (tâche 7.4), déjà écrits dans les enregistrements.
extension BrowserSession {
    /// Ce que la synchro a changé dans les enregistrements.
    struct SyncChanges {
        var profiles = false
        var spaces = false
        /// Spaces dont les onglets ou les dossiers ont changé.
        var spaceContents: Set<UUID> = []
        /// Profils dont les favoris ont changé.
        var favorites: Set<UUID> = []
    }

    /// Met les profils, les Spaces et leurs onglets en accord avec les enregistrements : un Space reçu s'ouvre, un Space
    /// passé à un autre profil se rouvre avec les données de ce profil, l'ordre et les thèmes suivent, et chaque Space
    /// touché reprend ses onglets (`TabManager.reconcile`).
    func reload(after changes: SyncChanges) {
        if changes.profiles {
            refreshProfiles()
        }
        if changes.spaces {
            reloadSpaces()
        }
        for space in spaces {
            let profileID = space.record.profile?.id
            guard changes.spaceContents.contains(space.id) || profileID.map(changes.favorites.contains) == true else {
                continue
            }
            let (tabs, layout) = space.store.load()
            space.tabManager.reconcile(tabs: tabs, layout: layout)
        }
    }

    private func reloadSpaces() {
        let context = container.mainContext
        let records = (try? context.fetch(FetchDescriptor<SpaceRecord>())) ?? []
        // Passé à un autre profil : ses onglets changent de cookies, le Space se rouvre depuis ses enregistrements (déjà à
        // jour : l'enregistrer maintenant mêlerait les favoris des deux profils).
        for space in spaces where space.openedProfileID != space.record.profile?.id {
            handOverFavorites(from: space, saving: false)
            space.close()
            removeSpace(space)
            openSpace(space.record)
        }
        // Space reçu : ses onglets sont là, aucun n'est sélectionné (rien ne se charge de lui-même à son affichage).
        for record in records where !spaces.contains(where: { $0.record === record }) {
            openSpace(record).tabManager.restoreSelection(nil)
        }
        sortSpaces()
        spaces.forEach { $0.reloadTheme() }
    }
}
