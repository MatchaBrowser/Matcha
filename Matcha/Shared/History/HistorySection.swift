import Foundation

nonisolated struct HistorySection: Identifiable, Hashable, Sendable {
    let day: HistoryDay
    /// Start of the day.
    let start: Date
    /// From the most recent to the oldest.
    let rows: [HistoryRow]

    var id: Date {
        start
    }
}
