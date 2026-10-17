import Foundation

/// Période effacée par « Effacer l'historique… », comme dans Safari.
nonisolated enum HistoryPeriod: String, CaseIterable, Identifiable, Sendable {
    case lastHour
    case today
    case todayAndYesterday
    case allHistory

    var id: Self {
        self
    }

    /// Début des visites effacées : il y a une heure, minuit, la veille à minuit (selon `calendar`, son fuseau et ses
    /// changements d'heure) ; nil pour tout l'historique. Tout ce qui suit est effacé.
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
