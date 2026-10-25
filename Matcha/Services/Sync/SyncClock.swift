import Foundation

/// Hybrid clock of sync (`SYNC.md` § 2.8): each modification written here is dated after everything this Mac has
/// already written or received, and after the version it replaces, even if its clock is behind. A received date more
/// than 24 hours ahead of this Mac doesn't move the clock: a Mac set in the future would otherwise win every conflict,
/// and spread its date to all Macs. To the millisecond. Pure type.
nonisolated struct SyncClock: Codable, Equatable, Sendable {
    /// Beyond this lead over this Mac's time, a received date is not taken into account.
    static let maximumLead: TimeInterval = 24 * 60 * 60

    /// Latest date written or received, in milliseconds since 1970.
    private(set) var latest: Int64 = 0

    /// Date of a new modification: the Mac's time, or 1 ms after the latest known date and after `replaced` (date of
    /// the content it replaces). A replaced date more than 24 hours ahead dates this modification only: the clock
    /// doesn't follow it, so the next modifications of this Mac aren't dated in the future too (review SY8).
    mutating func next(now: Date = .now, after replaced: Date? = nil) -> Date {
        let current = SyncCoding.milliseconds(of: now)
        let floor = replaced.map { SyncCoding.milliseconds(of: $0) + 1 } ?? Int64.min
        let candidate = max(current, latest + 1)
        guard floor > candidate else {
            latest = candidate
            return SyncCoding.date(milliseconds: candidate)
        }
        latest = floor <= current + Int64(Self.maximumLead * 1000) ? floor : candidate
        return SyncCoding.date(milliseconds: floor)
    }

    /// Date of a received modification; false if it is too far ahead of this Mac to be taken into account.
    @discardableResult
    mutating func observe(_ date: Date, now: Date = .now) -> Bool {
        guard date.timeIntervalSince(now) <= Self.maximumLead else {
            return false
        }
        latest = max(latest, SyncCoding.milliseconds(of: date))
        return true
    }
}
