import Foundation
@testable import Matcha
import Testing

/// `Retry-After` read from an error answer (review SY3): never a wait that traps or loops.
struct SyncRetryAfterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [
        ("30", 30.0),
        (" 120 ", 120),
        ("0", SyncRetryAfter.shortest),
        ("86400", SyncRetryAfter.longest),
        ("99999999999999999999999", SyncRetryAfter.longest),
    ] as [(String, TimeInterval)])
    func `a number of seconds is kept between the bounds`(header: String, expected: TimeInterval) {
        #expect(SyncRetryAfter.seconds(from: header, now: now) == expected)
    }

    @Test(arguments: ["inf", "nan", "1e40", "-5", "2.5", "soon", ""])
    func `a header that is not a number of seconds nor a date is ignored`(header: String) {
        #expect(SyncRetryAfter.seconds(from: header, now: now) == nil)
    }

    @Test func `an http date gives the time left, kept between the bounds`() {
        // `now` is Fri, 15 Jan 2027 08:00:00 GMT.
        #expect(SyncRetryAfter.seconds(from: "Fri, 15 Jan 2027 08:01:30 GMT", now: now) == 90)
        #expect(SyncRetryAfter.seconds(from: "Fri, 15 Jan 2027 07:00:00 GMT", now: now) == SyncRetryAfter.shortest)
        #expect(SyncRetryAfter.seconds(from: "Sat, 16 Jan 2027 08:00:00 GMT", now: now) == SyncRetryAfter.longest)
    }

    @Test func `no header, no wait`() {
        #expect(SyncRetryAfter.seconds(from: nil, now: now) == nil)
    }
}
