import Foundation
import Observation
import OSLog
import SwiftData

/// Historique de navigation (tâche 5.5) : les visites enregistrées (`HistoryRecord`) et leur index en mémoire, un par
/// profil (`HistoryIndex`), que lisent la barre de commande et la fenêtre de l'historique. L'index est lu une seule
/// fois, hors du fil principal (`HistoryLoader`), après l'effacement des visites de plus d'un an ; ce qui change
/// pendant cette lecture est rejoué ensuite. Une fenêtre privée n'a pas de magasin : rien n'est retenu.
@MainActor
@Observable
final class HistoryStore {
    /// Change à chaque modification de l'historique lu : les vues qui le montrent se mettent à jour.
    private(set) var revision = 0
    private(set) var isLoaded = false

    /// Horloge des visites (remplacée dans les tests).
    @ObservationIgnored let now: () -> Date
    /// Calendrier des périodes effacées et de la durée de conservation.
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var indexes: [UUID?: HistoryIndex] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Changements faits pendant la lecture, rejoués ensuite.
    @ObservationIgnored private var pendingChanges: [HistoryChange] = []
    /// Dernières visites écrites, pour leur titre et leur rafraîchissement sans parcourir la base.
    @ObservationIgnored private var recentRecords: [(id: UUID, record: HistoryRecord)] = []

    init(container: ModelContainer, now: @escaping () -> Date = { .now }, calendar: Calendar = .autoupdatingCurrent) {
        self.container = container
        self.now = now
        self.calendar = calendar
    }

    private var context: ModelContext {
        container.mainContext
    }

    // MARK: Lecture

    /// Lit l'historique (une seule fois, lancée au démarrage de l'app) et attend la fin de la lecture.
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

    /// Historique du profil, nil tant qu'il n'est pas lu.
    func index(for profileID: UUID?) -> HistoryIndex? {
        isLoaded ? indexes[profileID] ?? HistoryIndex() : nil
    }

    /// Adresses du profil qui correspondent à `query`, pour la barre de commande (`HistoryIndex.entries`) : cherchées
    /// hors du fil principal, dans une copie de l'index ; une frappe plus récente (tâche annulée) arrête la recherche.
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

    // MARK: Visites

    /// Enregistre une visite de `url` (déjà retenue par `HistoryRecordingPolicy.storedURL`) maintenant.
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

    /// Prolonge la visite `id` (même page rechargée peu après) : date de maintenant, et `title` s'il n'est pas vide.
    /// Faux si elle n'existe plus (historique effacé entre-temps).
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

    /// Titre arrivé après la visite `id` ; sans effet si elle n'existe plus.
    func setTitle(_ title: String?, ofVisit id: UUID, profileID: UUID?) {
        guard let record = record(id) else {
            return
        }
        record.title = HistoryRecordingPolicy.normalizedTitle(title)
        save()
        apply(.setTitle(title, visitID: id, profileID: profileID))
    }

    // MARK: Primitives de `+Deletion`

    func apply(_ change: HistoryChange) {
        guard isLoaded else {
            // Pas encore lu : la lecture trouvera la base à jour ; en cours de lecture, le changement sera rejoué.
            if loadTask != nil {
                pendingChanges.append(change)
            }
            return
        }
        change.apply(to: &indexes)
        revision += 1
    }

    /// Visites supprimées de la base : celles gardées de côté ne servent plus.
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
