import Foundation
import SwiftData

/// The session after changes received from another Mac (task 7.4), already written to the records.
extension BrowserSession {
    /// What sync changed in the records.
    struct SyncChanges {
        var profiles = false
        var spaces = false
        /// Spaces whose tabs or folders changed.
        var spaceContents: Set<UUID> = []
        /// Profiles whose favorites changed.
        var favorites: Set<UUID> = []
    }

    /// Brings the profiles, the Spaces and their tabs in line with the records: a received Space opens, a Space moved
    /// to another profile reopens with that profile's data, order and themes follow, and each affected Space reloads
    /// its tabs (`TabManager.reconcile`).
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
        // Moved to another profile: its tabs change cookies, so the Space reopens from its records (already up to date:
        // saving it now would mix the favorites of both profiles).
        for space in spaces where space.openedProfileID != space.record.profile?.id {
            handOverFavorites(from: space, saving: false)
            space.close()
            removeSpace(space)
            openSpace(space.record)
        }
        // Received Space: its tabs are there, none is selected (nothing loads by itself when it is shown).
        for record in records where !spaces.contains(where: { $0.record === record }) {
            openSpace(record).tabManager.restoreSelection(nil)
        }
        sortSpaces()
        spaces.forEach { $0.reloadTheme() }
    }
}
