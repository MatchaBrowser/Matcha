import Foundation

/// Wait before the event stream reconnects (`SYNC.md` § 4.6): right away after a renewal of the token, unless the
/// previous one was less than 30 seconds ago (a server that says `expired` at each connection, review SY18); after any
/// other cut, a delay growing from 1 second to 5 minutes. Pure type (review TS8).
nonisolated struct SyncReconnectDelay {
    static let maximum: Duration = .seconds(5 * 60)
    /// Two renewals closer than this: the second reconnection waits.
    static let minimumRenewalInterval: Duration = .seconds(30)

    /// The next growing wait.
    private(set) var delay: Duration = .seconds(1)
    private var lastRenewal: ContinuousClock.Instant?

    /// The connection ended for a renewal, at `now`.
    mutating func afterRenewal(at now: ContinuousClock.Instant) -> Duration {
        defer { lastRenewal = now }
        guard let lastRenewal, now - lastRenewal < Self.minimumRenewalInterval else {
            delay = .seconds(1)
            return .zero
        }
        return grow()
    }

    /// The connection was cut, or refused.
    mutating func afterCut() -> Duration {
        grow()
    }

    private mutating func grow() -> Duration {
        defer { delay = min(delay * 2, Self.maximum) }
        return delay
    }
}
