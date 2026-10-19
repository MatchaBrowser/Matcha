import Foundation
@testable import Matcha
import Testing

/// Termination of a page's process (task 5.7): what to do, and when a page crashes in a loop.
struct PageCrashPolicyTests {
    @Test func `a visible page reloads at once`() {
        #expect(PageCrashPolicy.action(isVisible: true, recentTerminations: 1) == .reload)
    }

    @Test func `a hidden page reloads when it is shown`() {
        #expect(PageCrashPolicy.action(isVisible: false, recentTerminations: 1) == .reloadWhenShown)
    }

    @Test(arguments: [true, false], [2, 3, 10])
    func `repeated terminations show the message`(isVisible: Bool, terminations: Int) {
        #expect(PageCrashPolicy.action(isVisible: isVisible, recentTerminations: terminations) == .showProblem)
    }

    @Test func `the counter counts terminations of the last 30 seconds`() {
        var counter = PageCrashCounter()
        #expect(counter.record(at: fixedNow) == 1)
        #expect(counter.record(at: fixedNow.addingTimeInterval(10)) == 2)
        #expect(counter.record(at: fixedNow.addingTimeInterval(29)) == 3)
        // 30 s after the first one: it no longer counts.
        #expect(counter.record(at: fixedNow.addingTimeInterval(30)) == 3)
        #expect(counter.terminations.first == fixedNow.addingTimeInterval(10))
    }

    @Test func `terminations far apart each count alone`() {
        var counter = PageCrashCounter()
        #expect(counter.record(at: fixedNow) == 1)
        #expect(counter.record(at: fixedNow.addingTimeInterval(31)) == 1)
        #expect(counter.record(at: fixedNow.addingTimeInterval(120)) == 1)
        #expect(counter.terminations == [fixedNow.addingTimeInterval(120)])
    }

    @Test func `a termination dated later than now is forgotten`() {
        var counter = PageCrashCounter()
        _ = counter.record(at: fixedNow)
        // System clock set back by an hour.
        #expect(counter.record(at: fixedNow.addingTimeInterval(-3600)) == 1)
    }

    /// Two terminations within 30 s: the page is reloaded once, then waits for the user.
    @Test func `a page that crashes again right after its reload waits for the user`() {
        var counter = PageCrashCounter()
        let first = PageCrashPolicy.action(isVisible: true, recentTerminations: counter.record(at: fixedNow))
        let second = PageCrashPolicy.action(isVisible: true, recentTerminations: counter.record(at: fixedNow.addingTimeInterval(5)))
        let later = PageCrashPolicy.action(isVisible: true, recentTerminations: counter.record(at: fixedNow.addingTimeInterval(60)))
        #expect([first, second, later] == [.reload, .showProblem, .reload])
    }
}
