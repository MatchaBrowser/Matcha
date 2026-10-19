import Foundation
@testable import Matcha
import Testing
import WebKit

/// Context menu choice waiting for its window (task 5.9): handed over only once, to the only window that can come from
/// the menu, within a second.
struct PageMenuIntentTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let point = CGPoint(x: 0.25, y: 0.75)
    /// The window WebKit opens for a menu item (verified): `.other`, no size.
    private let menuWindow = PageMenuWindowRequest(navigationType: .other, opensPopupWindow: false)

    private func pending(_ destination: PageMenuDestination = .backgroundTab) -> PendingPageMenuIntent {
        var pending = PendingPageMenuIntent()
        pending.choose(destination, openingPoint: point, at: start)
        return pending
    }

    @Test func `the choice is given once to the window of the menu`() {
        var pending = pending(.peek)
        let intent = pending.take(for: menuWindow, at: start.addingTimeInterval(0.05))
        #expect(intent?.destination == .peek)
        #expect(intent?.openingPoint == point)
        #expect(pending.intent == nil)
        // The next window (a `window.open` from the page) follows the usual rules.
        #expect(pending.take(for: menuWindow, at: start.addingTimeInterval(0.1)) == nil)
    }

    @Test func `a page window is never taken without a choice`() {
        var pending = PendingPageMenuIntent()
        #expect(pending.take(for: menuWindow, at: start) == nil)
    }

    @Test func `the choice expires after one second`() {
        var pending = pending()
        #expect(pending.take(for: menuWindow, at: start.addingTimeInterval(PageMenuIntent.lifetime + 0.01)) == nil)
        #expect(pending.intent == nil)

        var onTime = self.pending()
        #expect(onTime.take(for: menuWindow, at: start.addingTimeInterval(PageMenuIntent.lifetime)) != nil)
    }

    /// A `target=_blank` link, a form, a sign-in window: never the menu's window, which may still arrive.
    @Test(arguments: [
        PageMenuWindowRequest(navigationType: .linkActivated, opensPopupWindow: false),
        PageMenuWindowRequest(navigationType: .formSubmitted, opensPopupWindow: false),
        PageMenuWindowRequest(navigationType: .other, opensPopupWindow: true),
    ])
    func `a window the menu cannot open leaves the choice pending`(request: PageMenuWindowRequest) {
        var pending = pending()
        #expect(pending.take(for: request, at: start.addingTimeInterval(0.01)) == nil)
        #expect(pending.intent != nil)
        #expect(pending.take(for: menuWindow, at: start.addingTimeInterval(0.02))?.destination == .backgroundTab)
    }

    @Test func `cancel forgets the choice`() {
        var pending = pending()
        pending.cancel()
        #expect(pending.take(for: menuWindow, at: start) == nil)
    }

    @Test func `a new choice replaces the previous one`() {
        var pending = pending(.peek)
        let later = start.addingTimeInterval(0.5)
        pending.choose(.backgroundTab, openingPoint: .zero, at: later)
        #expect(pending.intent == PageMenuIntent(destination: .backgroundTab, openingPoint: .zero, deadline: later.addingTimeInterval(1)))
    }
}
