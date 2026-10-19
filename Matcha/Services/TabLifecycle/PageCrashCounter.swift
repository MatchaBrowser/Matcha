import Foundation

/// Recent terminations of a page's process (task 5.7): those of the last `window` seconds. Two terminations this close
/// to each other make a loop (the page crashes again right after its automatic reload): `PageCrashPolicy` then stops
/// reloading it on its own.
nonisolated struct PageCrashCounter: Equatable, Sendable {
    /// Duration during which a termination counts.
    static let window: TimeInterval = 30

    /// Dates of the terminations still counted, from oldest to most recent.
    private(set) var terminations: [Date] = []

    /// Records a termination at `date` and returns the number of terminations in the last `window` seconds, this one
    /// included. A termination dated after `date` (system clock set back) is forgotten.
    mutating func record(at date: Date) -> Int {
        terminations = terminations.filter { (0 ..< Self.window).contains(date.timeIntervalSince($0)) } + [date]
        return terminations.count
    }
}
