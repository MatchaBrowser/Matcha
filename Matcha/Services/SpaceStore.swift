import Foundation
import Observation
import OSLog
import SwiftData

/// Saves a Space's tabs (pinned, Today, folders) and its profile's favorites in SwiftData, and reloads them at launch.
@MainActor
final class SpaceStore {
    /// Delay between a change and its saving: close changes are grouped.
    static let saveDelay = Duration.seconds(1)

    let space: SpaceRecord
    private let context: ModelContext
    private var pendingSave: Task<Void, Never>?
    /// True once the Space is deleted: nothing is saved anymore.
    private var isStopped = false
    /// True if this Space holds its profile's favorites: otherwise they are neither written nor deleted
    /// (`BrowserSession+Favorites`). Always true outside a session (tests).
    var savesFavorites: () -> Bool = { true }

    init(space: SpaceRecord, context: ModelContext) {
        self.space = space
        self.context = context
    }

    // MARK: Loading

    /// Saved tabs and their arrangement. Archived tabs are not reloaded.
    func load() -> (tabs: [StoredTab], layout: SidebarLayout) {
        let records = tabRecords().filter { $0.place != nil }
        var positions: [UUID: SidebarPosition] = [:]
        for record in records {
            if let place = record.place {
                positions[record.id] = SidebarPosition(
                    place: place,
                    order: record.order,
                    folderID: record.folder?.id,
                    splitGroupID: record.splitGroupID,
                    splitFraction: record.splitFraction,
                )
            }
        }
        let folders = (space.folders ?? []).map { folder in
            FolderEntry(
                id: folder.id,
                name: folder.name,
                isCollapsed: folder.isCollapsed,
                parentID: folder.parent?.id,
                order: folder.order,
                appearance: folder.appearance,
            )
        }
        let tabs = records.map { record in
            StoredTab(
                id: record.id,
                url: record.url,
                title: record.title,
                pinnedURL: record.pinnedURL,
                pinnedTitle: record.pinnedTitle,
                lastActivity: record.lastActivity,
                interactionState: record.interactionState,
            )
        }
        return (tabs, SidebarLayout(positions: positions, folders: folders))
    }

    // MARK: Saving

    /// Saves `manager` one second after each change of what is saved (arrangement, addresses, titles, activity), as
    /// long as the store and the manager exist.
    func startAutosave(of manager: TabManager) {
        withObservationTracking {
            _ = manager.layout
            _ = manager.storedTabs()
        } onChange: { [weak self, weak manager] in
            Task { @MainActor in
                guard let self, let manager else {
                    return
                }
                self.scheduleSave(of: manager)
                self.startAutosave(of: manager)
            }
        }
    }

    /// Saves right away (app quitting), cancelling the deferred save.
    func saveNow(_ manager: TabManager) {
        pendingSave?.cancel()
        pendingSave = nil
        guard !isStopped else {
            return
        }
        save(tabs: manager.storedTabs(), layout: manager.layout)
    }

    /// Stops saving anything (Space deleted).
    func stop() {
        isStopped = true
        pendingSave?.cancel()
        pendingSave = nil
    }

    private func scheduleSave(of manager: TabManager) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self, weak manager] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self, let manager else {
                return
            }
            saveNow(manager)
        }
    }

    /// Updates the records: creates what is missing, deletes the closed tabs and folders. Archived tabs are kept.
    func save(tabs: [StoredTab], layout: SidebarLayout) {
        let folders = saveFolders(layout.folderEntries)
        let positions = layout.positions
        let includesFavorites = savesFavorites()
        let records = includesFavorites ? tabRecords() : space.tabs ?? []
        var existing = Dictionary(records.map { ($0.id, $0) }) { first, _ in first }
        for stored in tabs {
            guard let position = positions[stored.id], includesFavorites || position.place != .favorite else {
                continue
            }
            let record = existing.removeValue(forKey: stored.id) ?? insertedTab(id: stored.id)
            record.url = stored.url
            record.title = stored.title
            record.pinnedURL = stored.pinnedURL
            record.pinnedTitle = stored.pinnedTitle
            record.lastActivity = stored.lastActivity
            record.interactionState = stored.interactionState
            record.place = position.place
            record.order = position.order
            record.folder = position.folderID.flatMap { folders[$0] }
            // Never a split for a favorite (`positions` does not give one).
            record.splitGroupID = position.splitGroupID
            record.splitFraction = position.splitFraction
            // A favorite belongs to the profile, the other tabs to the Space.
            record.profile = position.place == .favorite ? space.profile : nil
            record.space = position.place == .favorite ? nil : space
        }
        for leftover in existing.values where leftover.place != nil {
            context.delete(leftover)
        }
        do {
            try context.save()
        } catch {
            Logger.app.error("Enregistrement du Space impossible : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Updates the Space's folders and returns the records by identifier.
    private func saveFolders(_ entries: [FolderEntry]) -> [UUID: FolderRecord] {
        var existing = Dictionary((space.folders ?? []).map { ($0.id, $0) }) { first, _ in first }
        var saved: [UUID: FolderRecord] = [:]
        for entry in entries {
            let record = existing.removeValue(forKey: entry.id) ?? {
                let folder = FolderRecord(id: entry.id, name: entry.name)
                context.insert(folder)
                return folder
            }()
            record.name = entry.name
            record.order = entry.order
            record.isCollapsed = entry.isCollapsed
            record.appearance = entry.appearance
            record.space = space
            saved[entry.id] = record
        }
        for entry in entries {
            saved[entry.id]?.parent = entry.parentID.flatMap { saved[$0] }
        }
        for leftover in existing.values {
            context.delete(leftover)
        }
        return saved
    }

    /// Tabs of the Space and favorites of its profile.
    private func tabRecords() -> [TabRecord] {
        (space.tabs ?? []) + (space.profile?.favorites ?? [])
    }

    private func insertedTab(id: UUID) -> TabRecord {
        let record = TabRecord(id: id)
        context.insert(record)
        return record
    }
}
