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
    /// True if this Space saves its profile's favorites, the same in each of its Spaces: otherwise they are neither
    /// written nor deleted here (`BrowserSession+Favorites`). Always true outside a session (tests).
    var savesFavorites: () -> Bool = { true }
    /// Tabs of the windows of their own tabs that came from this Space (`WindowTabs`): saved at the top of its today
    /// tabs as long as their window is open, so that a crash doesn't lose them (review ON7). None outside a session.
    var windowTabs: () -> [StoredTab] = { [] }
    /// Navigation state last read or written for each tab: an unchanged one isn't written again (audit R8).
    private var savedStates: [UUID: Data?] = [:]

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
        savedStates = records.reduce(into: [:]) { $0[$1.id] = $1.interactionState }
        let tabs = records.map { record in
            StoredTab(
                id: record.id,
                url: record.url,
                title: record.title,
                pinnedURL: record.pinnedURL,
                pinnedTitle: record.pinnedTitle,
                lastActivity: record.lastActivity,
                interactionState: record.interactionState,
                fileReadAccess: record.fileReadAccess,
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
            _ = windowTabs()
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
        let (tabs, layout) = content(of: manager)
        save(tabs: tabs, layout: layout)
    }

    /// The tabs of `manager` to save, with those of the windows of their own tabs at the top of the today tabs.
    private func content(of manager: TabManager) -> (tabs: [StoredTab], layout: SidebarLayout) {
        let detached = windowTabs()
        guard !detached.isEmpty else {
            return (manager.storedTabs(), manager.layout)
        }
        var layout = manager.layout
        for (index, tab) in detached.enumerated() {
            layout.insertToday(tab.id, at: index)
        }
        return (detached + manager.storedTabs(), layout)
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

    /// Updates the records: creates what is missing, deletes the closed tabs and folders. Archived tabs are kept. Only
    /// what changed is assigned: an unchanged tab, and above all its navigation state (stored outside the database),
    /// isn't written again at each save (audit R8).
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
            update(record, \.url, to: stored.url)
            update(record, \.title, to: stored.title)
            update(record, \.pinnedURL, to: stored.pinnedURL)
            update(record, \.pinnedTitle, to: stored.pinnedTitle)
            update(record, \.lastActivity, to: stored.lastActivity)
            update(record, \.fileReadAccess, to: stored.fileReadAccess)
            if savedStates[stored.id] != stored.interactionState {
                record.interactionState = stored.interactionState
                savedStates[stored.id] = stored.interactionState
            }
            update(record, \.place, to: position.place)
            update(record, \.order, to: position.order)
            update(record, \.folder, to: position.folderID.flatMap { folders[$0] })
            // Never a split for a favorite (`positions` does not give one).
            update(record, \.splitGroupID, to: position.splitGroupID)
            update(record, \.splitFraction, to: position.splitFraction)
            // A favorite belongs to the profile, the other tabs to the Space.
            update(record, \.profile, to: position.place == .favorite ? space.profile : nil)
            update(record, \.space, to: position.place == .favorite ? nil : space)
        }
        for leftover in existing.values where leftover.place != nil {
            savedStates[leftover.id] = nil
            context.delete(leftover)
        }
        do {
            try context.save()
        } catch {
            Logger.app.error("Space not saved: \(error.logSummary, privacy: .public)")
        }
    }

    /// Assigns `value` only if it differs: an unchanged record stays out of the save.
    private func update<Record, Value: Equatable>(_ record: Record, _ keyPath: ReferenceWritableKeyPath<Record, Value>, to value: Value) {
        if record[keyPath: keyPath] != value {
            record[keyPath: keyPath] = value
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
            update(record, \.name, to: entry.name)
            update(record, \.order, to: entry.order)
            update(record, \.isCollapsed, to: entry.isCollapsed)
            if record.appearance != entry.appearance {
                record.appearance = entry.appearance
            }
            update(record, \.space, to: space)
            saved[entry.id] = record
        }
        for entry in entries {
            if let record = saved[entry.id] {
                update(record, \.parent, to: entry.parentID.flatMap { saved[$0] })
            }
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

    /// Record of a tab that is new to this Space: the one it had elsewhere (a favorite or a tab coming from another
    /// Space, whose Space may save later: never two records for one tab), otherwise a new one.
    private func insertedTab(id: UUID) -> TabRecord {
        if let existing = try? context.fetch(FetchDescriptor<TabRecord>(predicate: #Predicate { $0.id == id })).first {
            return existing
        }
        let record = TabRecord(id: id)
        context.insert(record)
        return record
    }
}
