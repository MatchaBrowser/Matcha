import Foundation
import Observation

/// State of the history window (⌘Y): profile shown, searched text, displayed sections and selected rows. The
/// sections are recomputed off the main thread (a year of history can amount to tens of thousands of visits) on
/// every change of the history, the profile or the searched text.
@MainActor
@Observable
final class HistoryWindowModel {
    let store: HistoryStore
    /// Profile shown (`MiniWindowManager.historyProfile`); changing the profile clears the selection.
    var profileID: UUID? {
        didSet {
            if profileID != oldValue {
                selection = []
            }
        }
    }

    var searchText = ""
    var selection: Set<HistoryRow.ID> = []
    private(set) var sections: [HistorySection] = []
    /// True once the first sections are computed (before that: a progress indicator rather than “No History”).
    private(set) var isReady = false

    init(store: HistoryStore, profileID: UUID?) {
        self.store = store
        self.profileID = profileID
    }

    /// What requires recomputing the sections.
    struct RefreshKey: Equatable {
        let revision: Int
        let profileID: UUID?
        let searchText: String
    }

    var refreshKey: RefreshKey {
        RefreshKey(revision: store.revision, profileID: profileID, searchText: searchText)
    }

    /// Recomputes the sections; a task cancelled in the meantime (new keystroke) displays nothing.
    func refresh() async {
        await store.load()
        guard let index = store.index(for: profileID) else {
            return
        }
        let sections = await HistoryList.build(from: index, search: searchText, now: store.now(), calendar: store.calendar)
        guard !Task.isCancelled else {
            return
        }
        self.sections = sections
        isReady = true
        let shown = Set(sections.flatMap { $0.rows.map(\.id) })
        if !selection.isSubset(of: shown) {
            selection.formIntersection(shown)
        }
    }

    /// Displayed rows among `ids`, in the list's order.
    func rows(_ ids: Set<HistoryRow.ID>) -> [HistoryRow] {
        sections.flatMap(\.rows).filter { ids.contains($0.id) }
    }

    /// Deletes all the visits of these rows.
    func delete(_ ids: Set<HistoryRow.ID>) {
        let visits = Set(rows(ids).flatMap(\.visitIDs))
        store.deleteVisits(visits, profileID: profileID)
        selection.subtract(ids)
    }

    func clear(_ period: HistoryPeriod) {
        store.clear(period, profileID: profileID)
        selection = []
    }
}
