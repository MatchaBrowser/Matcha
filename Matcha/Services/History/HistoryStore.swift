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
    private(set) var isLoaded = false

    /// Clock of the visits (replaced in tests).
    @ObservationIgnored let now: () -> Date
    /// Calendar of the erased periods and of the retention period.
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var indexes: [UUID?: HistoryIndex] = [:]
    /// Revision of each profile's history (`revision(of:)`).
    @ObservationIgnored private var revisions: [UUID?: HistoryRevision] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Changes made during the read, replayed afterwards.
    @ObservationIgnored private var pendingChanges: [HistoryChange] = []
    /// Last visits written, for their title and their refresh without going through the database.
    @ObservationIgnored private var recentRecords: [(id: UUID, record: HistoryRecord)] = []
    /// Called once visits are deleted, and after the read for those deleted before: what was kept for the websites no
    /// longer visited can go (website icons, review SV1).
    @ObservationIgnored var onVisitsRemoved: (@MainActor () -> Void)?
    /// Visits deleted before the history was read.
    @ObservationIgnored private var removedBeforeLoad = false

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

    /// Changes on every modification of the profile's loaded history: the views that show it update, never for another
    /// profile's visit (review SV10).
    func revision(of profileID: UUID?) -> Int {
        revisionCounter(of: profileID).value
    }

    private func revisionCounter(of profileID: UUID?) -> HistoryRevision {
        if let counter = revisions[profileID] {
            return counter
        }
        let counter = HistoryRevision()
        revisions[profileID] = counter
        return counter
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

    /// Domains of the visits of every profile, gathered off the main thread.
    func visitedHosts() async -> Set<String> {
        await load()
        return await Self.hosts(of: Array(indexes.values))
    }

    private func finishLoading(_ loaded: [UUID?: HistoryIndex]) {
        indexes = loaded
        pendingChanges.forEach { $0.apply(to: &indexes) }
        pendingChanges = []
        isLoaded = true
        revisions.values.forEach { $0.value += 1 }
        if removedBeforeLoad {
            removedBeforeLoad = false
            onVisitsRemoved?()
        }
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
        Logger.history.debug("Visit recorded")
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
        revisionCounter(of: change.profileID).value += 1
    }

    /// Visits deleted from the database: those kept aside are no longer needed.
    func forgetRecentRecords() {
        recentRecords = []
    }

    /// Visits deleted and their changes applied: `onVisitsRemoved` now, or once the history is read.
    func visitsWereRemoved() {
        if isLoaded {
            onVisitsRemoved?()
        } else {
            removedBeforeLoad = true
        }
    }

    func deleteRecords(where predicate: Predicate<HistoryRecord>) {
        do {
            try context.delete(model: HistoryRecord.self, where: predicate)
        } catch {
            Logger.history.error("Visits not deleted: \(error.logSummary, privacy: .public)")
        }
    }

    func save() {
        do {
            try context.save()
        } catch {
            Logger.history.error("History not saved: \(error.logSummary, privacy: .public)")
        }
    }

    @concurrent
    private nonisolated static func hosts(of indexes: [HistoryIndex]) async -> Set<String> {
        Set(indexes.flatMap { $0.visits.values.compactMap { $0.url.host() } })
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
        do {
            return try context.fetch(descriptor).first
        } catch {
            // The visit then isn't updated (review TR4).
            Logger.history.error("History entry unreadable: \(error.logSummary, privacy: .public)")
            return nil
        }
    }
}

/// Revision of one profile's history (`HistoryStore.revision(of:)`).
@MainActor
@Observable
final class HistoryRevision {
    var value = 0
}
