import Foundation

/// Hybrid clock of sync (task 7.4, `SYNC.md` § 2.2): each modification written here is dated after everything this
/// Mac has already written or received, even if its clock is behind. To the millisecond. Pure type.
nonisolated struct SyncClock: Codable, Equatable, Sendable {
    /// Latest date written or received, in milliseconds since 1970.
    private(set) var latest: Int64 = 0

    /// Date of a new modification: the Mac's time, or 1 ms after the latest known date.
    mutating func next(now: Date = .now) -> Date {
        latest = max(SyncCoding.milliseconds(of: now), latest + 1)
        return SyncCoding.date(milliseconds: latest)
    }

    /// Date of a received modification.
    mutating func observe(_ date: Date) {
        latest = max(latest, SyncCoding.milliseconds(of: date))
    }
}
