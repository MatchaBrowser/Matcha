import Foundation

/// Jour d'une section de la fenêtre de l'historique.
nonisolated enum HistoryDay: Hashable, Sendable {
    case today
    case yesterday
    /// Début du jour.
    case date(Date)
}

/// Ligne de la fenêtre de l'historique : une adresse visitée un jour donné, toutes ses visites de ce jour réunies.
nonisolated struct HistoryRow: Identifiable, Hashable, Sendable {
    /// « <début du jour>|<clé d'adresse> ».
    let id: String
    let url: URL
    /// Dernier titre de l'adresse, sinon son adresse lisible.
    let title: String
    /// Domaine sans « www. », ou nom du fichier (`AddressDisplay.short`).
    let host: String
    /// Dernière visite de ce jour.
    let lastVisit: Date
    /// Visites de ce jour, supprimées avec la ligne.
    let visitIDs: [UUID]
}

nonisolated struct HistorySection: Identifiable, Hashable, Sendable {
    let day: HistoryDay
    /// Début du jour.
    let start: Date
    /// De la plus récente à la plus ancienne.
    let rows: [HistoryRow]

    var id: Date {
        start
    }
}

/// Contenu de la fenêtre de l'historique, pur : visites d'un profil regroupées par jour (le plus récent d'abord) et
/// par adresse, filtrées par le texte cherché.
nonisolated enum HistoryList {
    /// `search` : chaque mot doit se trouver dans le titre ou l'adresse, sans tenir compte de la casse, des accents
    /// ni de la largeur ; vide : tout.
    static func sections(from index: HistoryIndex, search: String, now: Date, calendar: Calendar) -> [HistorySection] {
        let tokens = CommandText.fold(search).split(separator: " ").map(String.init)
        let entries = tokens.isEmpty ? index.entries : index.entries.filter { matches($0.value, tokens: tokens) }
        let visits = index.visits.values
            .filter { entries[$0.urlKey] != nil }
            .sorted { HistoryIndex.isOlder($1, $0) }
        var sections: [HistorySection] = []
        var day: DateInterval?
        var rows: [String: (lastVisit: Date, ids: [UUID])] = [:]
        var order: [String] = []

        func closeDay() {
            guard let day else {
                return
            }
            let dayRows = order.compactMap { key -> HistoryRow? in
                guard let entry = entries[key], let group = rows[key] else {
                    return nil
                }
                return row(for: entry, dayStart: day.start, lastVisit: group.lastVisit, visitIDs: group.ids)
            }
            sections.append(HistorySection(day: Self.day(of: day.start, now: now, calendar: calendar), start: day.start, rows: dayRows))
        }

        for visit in visits {
            if day.map({ $0.start <= visit.date && visit.date < $0.end }) != true {
                closeDay()
                day = calendar.dateInterval(of: .day, for: visit.date)
                rows = [:]
                order = []
            }
            if rows[visit.urlKey] == nil {
                // Visites de la plus récente à la plus ancienne : la première est la dernière du jour.
                rows[visit.urlKey] = (visit.date, [])
                order.append(visit.urlKey)
            }
            rows[visit.urlKey]?.ids.append(visit.id)
        }
        closeDay()
        return sections
    }

    /// `sections(from:search:now:calendar:)` hors du fil principal (fenêtre de l'historique).
    @concurrent
    static func build(from index: HistoryIndex, search: String, now: Date, calendar: Calendar) async -> [HistorySection] {
        sections(from: index, search: search, now: now, calendar: calendar)
    }

    /// Chaque mot de `tokens` (repliés) se trouve dans le titre affiché ou l'adresse lisible.
    static func matches(_ entry: HistoryIndexEntry, tokens: [String]) -> Bool {
        let fields = entry.fields.titles + [entry.fields.address].compactMap(\.self)
        return tokens.allSatisfy { token in fields.contains { $0.contains(token) } }
    }

    static func day(of start: Date, now: Date, calendar: Calendar) -> HistoryDay {
        if calendar.isDate(start, inSameDayAs: now) {
            return .today
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(start, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .date(start)
    }

    private static func row(for entry: HistoryIndexEntry, dayStart: Date, lastVisit: Date, visitIDs: [UUID]) -> HistoryRow {
        HistoryRow(
            id: "\(dayStart.timeIntervalSinceReferenceDate)|\(entry.urlKey)",
            url: entry.url,
            title: entry.title ?? CommandText.displayURL(entry.url),
            host: AddressDisplay.short(for: entry.url),
            lastVisit: lastVisit,
            visitIDs: visitIDs,
        )
    }
}
