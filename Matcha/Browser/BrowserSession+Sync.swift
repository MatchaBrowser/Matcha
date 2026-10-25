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

    /// Received deletion of a Space (`SYNC.md` § 2.3), even the last one: `ensureSyncDefaults` restores the invariants
    /// afterwards. Its tabs and folders go with it. Its favorites are not saved: `MatchaSyncStore.apply` saved them
    /// before writing the batch, and saving them now would write their state from before the batch over the favorites
    /// it received (review ON3).
    func removeSpaceFromSync(_ space: SpaceSession) {
        space.close()
        removeSpace(space)
        container.mainContext.delete(space.record)
    }

    /// A session always has a profile and a Space (`SYNC.md` § 2.3, invariants). If received deletions left none, the
    /// first-launch ones come back under identifiers derived from the account's key, the same on all Macs: two Macs
    /// that recreate them write the same records, and the conflict rule keeps one. True if something was created.
    @discardableResult
    func ensureSyncDefaults(profileID: UUID, spaceID: UUID) -> Bool {
        let context = container.mainContext
        var created = false
        if profiles.isEmpty {
            context.insert(ProfileRecord(id: profileID, name: Self.defaultProfileName))
            refreshProfiles()
            created = true
        }
        if spaces.isEmpty {
            let record = SpaceRecord(id: spaceID, name: Self.defaultSpaceName, profile: profiles.first)
            context.insert(record)
            openSpace(record)
            created = true
        }
        return created
    }

    private func reloadSpaces() {
        let context = container.mainContext
        let records = (try? context.fetch(FetchDescriptor<SpaceRecord>())) ?? []
        // Moved to another profile: its tabs change cookies, so the Space reopens from its records (already up to date:
        // saving it now would mix the favorites of both profiles).
        for space in spaces where space.openedProfileID != space.record.profile?.id {
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
