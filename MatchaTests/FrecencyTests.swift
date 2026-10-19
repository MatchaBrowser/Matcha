import Foundation
@testable import Matcha
import Testing

private let day: TimeInterval = 86400

/// Age of the last visit and expected weight.
private let recencyCases: [(TimeInterval, Int)] = [
    (0, 100),
    (4 * day, 100),
    (4 * day + 1, 70),
    (14 * day, 70),
    (31 * day, 50),
    (90 * day, 30),
    (91 * day, 10),
    (-3600, 100),
]

struct FrecencyTests {
    @Test(arguments: recencyCases)
    func `recency weights by age`(age: TimeInterval, weight: Int) {
        #expect(Frecency.recencyWeight(age: age) == weight)
    }

    @Test func `score multiplies visits capped at thirty`() {
        let twoDaysAgo = fixedNow.addingTimeInterval(-2 * day)
        #expect(Frecency.score(visitCount: 10, lastVisit: twoDaysAgo, now: fixedNow) == 1000)
        #expect(Frecency.score(visitCount: 0, lastVisit: twoDaysAgo, now: fixedNow) == 100)
        #expect(Frecency.score(visitCount: 45, lastVisit: twoDaysAgo, now: fixedNow) == 3000)
        let twoMonthsAgo = fixedNow.addingTimeInterval(-60 * day)
        #expect(Frecency.score(visitCount: 30, lastVisit: twoMonthsAgo, now: fixedNow) == 900)
    }
}
