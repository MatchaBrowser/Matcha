import Foundation

/// Content of the history window, pure: a profile's visits grouped by day (most recent first) and by address,
/// filtered by the searched text.
nonisolated enum HistoryList {
    /// `search`: each word must be found in the title or the address, ignoring case, accents and width; empty:
    /// everything.
    static func sections(from index: HistoryIndex, search: String, now: Date, calendar: Calendar) -> [HistorySection] {
        let tokens = CommandText.fold(search).split(separator: " ").map(String.init)
        let entries = tokens.isEmpty ? index.entriesByKey : index.entriesByKey.filter { matches($0.value, tokens: tokens) }
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
                // Visits from the most recent to the oldest: the first is the day's last.
                rows[visit.urlKey] = (visit.date, [])
                order.append(visit.urlKey)
            }
            rows[visit.urlKey]?.ids.append(visit.id)
        }
        closeDay()
        return sections
    }

    /// `sections(from:search:now:calendar:)` off the main thread (history window).
    @concurrent
    static func build(from index: HistoryIndex, search: String, now: Date, calendar: Calendar) async -> [HistorySection] {
        sections(from: index, search: search, now: now, calendar: calendar)
    }

    /// Each word of `tokens` (folded) is found in the displayed title or the readable address.
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
