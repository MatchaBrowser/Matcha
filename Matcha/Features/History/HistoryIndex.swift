import Foundation

/// Historique d'un profil en mémoire (tâche 5.5) : chaque visite, et les adresses qui les regroupent par clé
/// (`CommandText.urlKey`) avec leur nombre de visites, leur dernière visite et leur dernier titre. Pur et sans
/// effet de bord ; chaque changement est idempotent (une visite est désignée par son identifiant), si bien qu'un
/// changement rejoué après le chargement de l'historique ne compte jamais deux fois.
nonisolated struct HistoryIndex: Sendable {
    private(set) var visits: [UUID: HistoryVisit] = [:]
    /// Adresses, par clé.
    private(set) var entries: [String: HistoryIndexEntry] = [:]
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

    /// Ajoute `visit`, ou remplace la visite de même identifiant.
    mutating func insert(_ visit: HistoryVisit) {
        if let previous = visits[visit.id], previous.urlKey != visit.urlKey {
            visitIDsByKey[previous.urlKey]?.remove(visit.id)
            rebuildEntry(previous.urlKey)
        }
        visits[visit.id] = visit
        visitIDsByKey[visit.urlKey, default: []].insert(visit.id)
        rebuildEntry(visit.urlKey)
    }

    /// Nouveau titre de la visite `id` (nil ou vide : sans titre) ; sans effet si elle n'existe plus.
    mutating func setTitle(_ title: String?, ofVisit id: UUID) {
        guard var visit = visits[id] else {
            return
        }
        visit.title = HistoryRecordingPolicy.normalizedTitle(title)
        insert(visit)
    }

    /// Visite `id` prolongée (`HistoryRecordingPolicy.Decision.refresh`) : nouvelle date, et nouveau titre s'il y en
    /// a un. Sans effet si elle n'existe plus.
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

    /// Retire ces visites ; les adresses qui n'en ont plus disparaissent.
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

    /// Retire les visites faites depuis `start` (compris), y compris celles datées dans le futur (heure du Mac
    /// changée entre-temps).
    mutating func remove(since start: Date) {
        remove(visits.values.filter { $0.date >= start }.map(\.id))
    }

    /// Recalcule l'adresse `key` d'après ses visites : la plus récente donne l'adresse, la plus récente qui a un
    /// titre donne le titre.
    private mutating func rebuildEntry(_ key: String) {
        let keyVisits = visitIDsByKey[key]?.compactMap { visits[$0] } ?? []
        guard let latest = keyVisits.max(by: Self.isOlder) else {
            visitIDsByKey[key] = nil
            entries[key] = nil
            return
        }
        let titled = keyVisits.filter { $0.title != nil }.max(by: Self.isOlder)
        entries[key] = HistoryIndexEntry(
            urlKey: key,
            url: latest.url,
            title: titled?.title,
            visitCount: keyVisits.count,
            lastVisit: latest.date,
            previous: entries[key],
        )
    }

    /// Ordre des visites : date, puis identifiant (deux visites à la même date restent dans un ordre stable).
    static func isOlder(_ lhs: HistoryVisit, _ rhs: HistoryVisit) -> Bool {
        lhs.date != rhs.date ? lhs.date < rhs.date : lhs.id.uuidString < rhs.id.uuidString
    }
}
