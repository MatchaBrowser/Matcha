import Foundation
import Observation

/// État de la fenêtre de l'historique (⌘Y) : profil montré, texte cherché, sections affichées et lignes choisies.
/// Les sections sont recalculées hors du fil principal (un an d'historique peut compter des dizaines de milliers de
/// visites) à chaque changement de l'historique, du profil ou du texte cherché.
@MainActor
@Observable
final class HistoryWindowModel {
    let store: HistoryStore
    /// Profil montré (`MiniWindowManager.historyProfile`) ; changer de profil vide la sélection.
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
    /// Vrai une fois les premières sections calculées (avant : indicateur d'attente plutôt que « Aucun historique »).
    private(set) var isReady = false

    init(store: HistoryStore, profileID: UUID?) {
        self.store = store
        self.profileID = profileID
    }

    /// Ce qui demande de recalculer les sections.
    struct RefreshKey: Equatable {
        let revision: Int
        let profileID: UUID?
        let searchText: String
    }

    var refreshKey: RefreshKey {
        RefreshKey(revision: store.revision, profileID: profileID, searchText: searchText)
    }

    /// Recalcule les sections ; une tâche annulée entre-temps (nouvelle frappe) n'affiche rien.
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

    /// Lignes affichées parmi `ids`, dans l'ordre de la liste.
    func rows(_ ids: Set<HistoryRow.ID>) -> [HistoryRow] {
        sections.flatMap(\.rows).filter { ids.contains($0.id) }
    }

    /// Supprime toutes les visites de ces lignes.
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
