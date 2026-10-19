import Foundation

/// Frequency and recency of a history address, as integers, in the manner of Firefox.
nonisolated enum Frecency {
    /// Beyond this, visits no longer count.
    static let maximumVisits = 30

    /// Weight of the last visit according to its age (bounds included): 100 up to 4 days, 70 up to 14, 50 up to
    /// 31, 30 up to 90, then 10. A negative age counts as zero.
    static func recencyWeight(age: TimeInterval) -> Int {
        let day: TimeInterval = 86400
        switch max(0, age) {
        case ...(4 * day): return 100
        case ...(14 * day): return 70
        case ...(31 * day): return 50
        case ...(90 * day): return 30
        default: return 10
        }
    }

    /// Recency weight multiplied by the number of visits (at least 1, at most 30).
    static func score(visitCount: Int, lastVisit: Date, now: Date) -> Int {
        recencyWeight(age: now.timeIntervalSince(lastVisit)) * min(max(visitCount, 1), maximumVisits)
    }
}
