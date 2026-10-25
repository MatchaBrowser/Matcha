import Foundation

/// A profile's history in memory (task 5.5): every visit, and the addresses that group them by key
/// (`CommandText.urlKey`) with their visit count, last visit and last title. Pure and free of side effects; each
/// change is idempotent (a visit is identified by its identifier), so a change replayed after the history has
/// loaded never counts twice.
nonisolated struct HistoryIndex: Sendable {
    private(set) var visits: [UUID: HistoryVisit] = [:]
    /// Addresses, by key.
    private(set) var entriesByKey: [String: HistoryIndexEntry] = [:]
    private var visitIDsByKey: [String: Set<UUID>] = [:]

    init(visits: [HistoryVisit] = []) {
        for visit in visits {
            self.visits[visit.id] = visit
            visitIDsByKey[visit.urlKey, default: []].insert(visit.id)
        }
        for key in visitIDsByKey.keys {
            rebuildEntry(key)
        }
    }

    var isEmpty: Bool {
        visits.isEmpty
    }

    /// Adds `visit`, or replaces the visit with the same identifier.
    mutating func insert(_ visit: HistoryVisit) {
        if let previous = visits[visit.id], previous.urlKey != visit.urlKey {
            visitIDsByKey[previous.urlKey]?.remove(visit.id)
            rebuildEntry(previous.urlKey)
        }
        visits[visit.id] = visit
        visitIDsByKey[visit.urlKey, default: []].insert(visit.id)
        rebuildEntry(visit.urlKey)
    }

    /// New title of visit `id` (nil or empty: untitled); no effect if it no longer exists.
    mutating func setTitle(_ title: String?, ofVisit id: UUID) {
        guard var visit = visits[id] else {
            return
        }
        visit.title = HistoryRecordingPolicy.normalizedTitle(title)
        insert(visit)
    }

    /// Visit `id` extended (`HistoryRecordingPolicy.Decision.refresh`): new date, and new title if there is one. No
    /// effect if it no longer exists.
    mutating func refresh(visit id: UUID, date: Date, title: String?) {
        guard var visit = visits[id] else {
            return
        }
        visit.date = date
        if let title = HistoryRecordingPolicy.normalizedTitle(title) {
            visit.title = title
        }
        insert(visit)
    }

    /// Removes these visits; addresses left without visits disappear.
    mutating func remove(_ ids: some Sequence<UUID>) {
        var keys: Set<String> = []
        for id in ids {
            guard let visit = visits.removeValue(forKey: id) else {
                continue
            }
            visitIDsByKey[visit.urlKey]?.remove(id)
            keys.insert(visit.urlKey)
        }
        keys.forEach { rebuildEntry($0) }
    }

    /// Removes the visits made since `start` (inclusive), including those dated in the future (Mac clock changed in
    /// the meantime).
    mutating func remove(since start: Date) {
        remove(visits.values.filter { $0.date >= start }.map(\.id))
    }

    /// Recomputes address `key` from its visits: the most recent gives the address, the most recent with a title
    /// gives the title.
    private mutating func rebuildEntry(_ key: String) {
        let keyVisits = visitIDsByKey[key]?.compactMap { visits[$0] } ?? []
        guard let latest = keyVisits.max(by: Self.isOlder) else {
            visitIDsByKey[key] = nil
            entriesByKey[key] = nil
            return
        }
        let titled = keyVisits.filter { $0.title != nil }.max(by: Self.isOlder)
        entriesByKey[key] = HistoryIndexEntry(
            urlKey: key,
            url: latest.url,
            title: titled?.title,
            visitCount: keyVisits.count,
            lastVisit: latest.date,
            previous: entriesByKey[key],
        )
    }

    /// Order of visits: date, then identifier (two visits at the same date stay in a stable order).
    static func isOlder(_ lhs: HistoryVisit, _ rhs: HistoryVisit) -> Bool {
        lhs.date != rhs.date ? lhs.date < rhs.date : lhs.id.uuidString < rhs.id.uuidString
    }
}
