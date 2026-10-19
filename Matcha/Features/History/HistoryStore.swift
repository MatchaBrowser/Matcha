import Foundation
import Observation
import OSLog
import SwiftData

/// Browsing history (task 5.5): the saved visits (`HistoryRecord`) and their in-memory index, one per profile
/// (`HistoryIndex`), read by the command bar and the history window. The index is read only once, off the main
/// thread (`HistoryLoader`), after visits older than a year are erased; whatever changes during that read is
/// replayed afterwards. A private window has no store: nothing is kept.
@MainActor
@Observable
final class HistoryStore {
    /// Changes on every modification of the loaded history: the views that show it update.
    private(set) var revision = 0
    private(set) var isLoaded = false

    /// Clock of the visits (replaced in tests).
    @ObservationIgnored let now: () -> Date
    /// Calendar of the erased periods and of the retention period.
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var indexes: [UUID?: HistoryIndex] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Changes made during the read, replayed afterwards.
    @ObservationIgnored private var pendingChanges: [HistoryChange] = []
    /// Last visits written, for their title and their refresh without going through the database.
    @ObservationIgnored private var recentRecords: [(id: UUID, record: HistoryRecord)] = []

    init(container: ModelContainer, now: @escaping () -> Date = { .now }, calendar: Calendar = .autoupdatingCurrent) {
        self.container = container
        self.now = now
        self.calendar = calendar
    }

    private var context: ModelContext {
        container.mainContext
    }

    // MARK: Reading

    /// Reads the history (only once, started at app launch) and waits for the read to finish.
    func load() async {
        if loadTask == nil {
            let container = container
            let cutoff = HistoryRecordingPolicy.retentionCutoff(now: now(), calendar: calendar)
            loadTask = Task { [weak self] in
                let loaded = await HistoryLoader.load(from: container, purgingBefore: cutoff)
                self?.finishLoading(loaded)
            }
        }
        await loadTask?.value
    }

    /// The profile's history, nil until it has been read.
    func index(for profileID: UUID?) -> HistoryIndex? {
        isLoaded ? indexes[profileID] ?? HistoryIndex() : nil
    }

    /// The profile's addresses that match `query`, for the command bar (`HistoryIndex.entries`): searched off the
    /// main thread, in a copy of the index; a more recent keystroke (cancelled task) stops the search.
    func entries(profileID: UUID?, matching query: CommandQuery, limit: Int) async -> [HistoryEntry] {
        await load()
        guard let index = indexes[profileID] else {
            return []
        }
        return await Self.search(index, query, limit: limit, now: now())
    }

    private func finishLoading(_ loaded: [UUID?: HistoryIndex]) {
        indexes = loaded
        pendingChanges.forEach { $0.apply(to: &indexes) }
        pendingChanges = []
        isLoaded = true
        revision += 1
    }

    // MARK: Visits

    /// Records a visit to `url` (already kept by `HistoryRecordingPolicy.storedURL`) now.
    @discardableResult
    func recordVisit(url: URL, title: String?, profileID: UUID?, spaceID: UUID?) -> HistoryVisit {
        let visit = HistoryVisit(url: url, title: title, date: now())
        let record = HistoryRecord(
            id: visit.id,
            url: visit.url,
            urlKey: visit.urlKey,
            title: visit.title,
            visitDate: visit.date,
            profileID: profileID,
            spaceID: spaceID,
        )
        context.insert(record)
        save()
        recentRecords.append((visit.id, record))
        if recentRecords.count > 50 {
            recentRecords.removeFirst()
        }
        apply(.insert(visit, profileID: profileID))
        Logger.history.debug("Visite retenue")
        return visit
    }

    /// Extends visit `id` (same page reloaded shortly after): the current date, and `title` if it is not empty.
    /// False if it no longer exists (history erased in the meantime).
    func refreshVisit(_ id: UUID, title: String?, profileID: UUID?) -> Bool {
        guard let record = record(id) else {
            return false
        }
        let date = now()
        record.visitDate = date
        if let title = HistoryRecordingPolicy.normalizedTitle(title) {
            record.title = title
        }
        save()
        apply(.refresh(visitID: id, date: date, title: title, profileID: profileID))
        return true
    }

    /// Title that arrived after visit `id`; no effect if it no longer exists.
    func setTitle(_ title: String?, ofVisit id: UUID, profileID: UUID?) {
        guard let record = record(id) else {
            return
        }
        record.title = HistoryRecordingPolicy.normalizedTitle(title)
        save()
        apply(.setTitle(title, visitID: id, profileID: profileID))
    }

    // MARK: Primitives for `+Deletion`

    func apply(_ change: HistoryChange) {
        guard isLoaded else {
            // Not read yet: the read will find the database up to date; while reading, the change will be replayed.
            if loadTask != nil {
                pendingChanges.append(change)
            }
            return
        }
        change.apply(to: &indexes)
        revision += 1
    }

    /// Visits deleted from the database: those kept aside are no longer needed.
    func forgetRecentRecords() {
        recentRecords = []
    }

    func deleteRecords(where predicate: Predicate<HistoryRecord>) {
        do {
            try context.delete(model: HistoryRecord.self, where: predicate)
        } catch {
            Logger.history.error("Visites non supprimées : \(error.localizedDescription, privacy: .public)")
        }
    }

    func save() {
        do {
            try context.save()
        } catch {
            Logger.history.error("Historique non enregistré : \(error.localizedDescription, privacy: .public)")
        }
    }

    @concurrent
    private nonisolated static func search(_ index: HistoryIndex, _ query: CommandQuery, limit: Int, now: Date) async -> [HistoryEntry] {
        index.entries(matching: query, limit: limit, now: now)
    }

    private func record(_ id: UUID) -> HistoryRecord? {
        if let recent = recentRecords.last(where: { $0.id == id })?.record, !recent.isDeleted, recent.modelContext != nil {
            return recent
        }
        let descriptor = FetchDescriptor<HistoryRecord>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}
