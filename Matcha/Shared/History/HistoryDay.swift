import Foundation

/// Day of a section in the history window.
nonisolated enum HistoryDay: Hashable, Sendable {
    case today
    case yesterday
    /// Start of the day.
    case date(Date)
}
