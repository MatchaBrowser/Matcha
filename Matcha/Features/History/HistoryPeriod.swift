import Foundation

/// Period erased by “Clear History…”, as in Safari.
nonisolated enum HistoryPeriod: String, CaseIterable, Identifiable, Sendable {
    case lastHour
    case today
    case todayAndYesterday
    case allHistory

    var id: Self {
        self
    }

    /// Start of the erased visits: an hour ago, midnight, the previous day at midnight (according to `calendar`, its
    /// time zone and its clock changes); nil for all history. Everything after it is erased.
    func start(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .lastHour:
            return now.addingTimeInterval(-3600)
        case .today:
            return calendar.startOfDay(for: now)
        case .todayAndYesterday:
            let today = calendar.startOfDay(for: now)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today).map(calendar.startOfDay(for:))
            return yesterday ?? today.addingTimeInterval(-86400)
        case .allHistory:
            return nil
        }
    }
}
