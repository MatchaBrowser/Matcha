import Foundation

/// Row of the history window: an address visited on a given day, with all its visits of that day merged.
nonisolated struct HistoryRow: Identifiable, Hashable, Sendable {
    /// “<start of day>|<address key>”.
    let id: String
    let url: URL
    /// Last title of the address, otherwise its readable address.
    let title: String
    /// Domain without “www.”, or file name (`AddressDisplay.short`).
    let host: String
    /// Last visit of that day.
    let lastVisit: Date
    /// Visits of that day, deleted with the row.
    let visitIDs: [UUID]
}
