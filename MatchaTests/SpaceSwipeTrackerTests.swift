@testable import Matcha
import Testing

struct SpaceSwipeTrackerTests {
    /// Joue un geste : un début puis des mouvements (doigts, vertical) ; renvoie les sens déclenchés.
    private func play(_ moves: [(Double, Double)]) -> [SpaceSwipeTracker.Direction] {
        var tracker = SpaceSwipeTracker()
        var directions: [SpaceSwipeTracker.Direction] = []
        for (index, move) in moves.enumerated() {
            let phase: SpaceSwipeTracker.Phase = index == 0 ? .began : .changed
            if let direction = tracker.handle(phase: phase, fingerDeltaX: move.0, deltaY: move.1) {
                directions.append(direction)
            }
        }
        _ = tracker.handle(phase: .ended, fingerDeltaX: 0, deltaY: 0)
        return directions
    }

    @Test func `fingers to the left go to the next space`() {
        #expect(play([(-10, 0), (-40, 2), (-40, 0)]) == [.next])
    }

    @Test func `fingers to the right go to the previous space`() {
        #expect(play([(30, 0), (30, 0), (30, 1)]) == [.previous])
    }

    @Test func `short swipes do nothing`() {
        #expect(play([(-20, 0), (-30, 0)]).isEmpty)
    }

    @Test func `mostly vertical gestures are scrolling`() {
        #expect(play([(-30, 40), (-30, 40), (-30, 40)]).isEmpty)
    }

    @Test func `a long swipe changes space only once`() {
        #expect(play([(-50, 0), (-50, 0), (-50, 0), (-50, 0)]) == [.next])
    }

    @Test func `movements without a beginning are ignored`() {
        var tracker = SpaceSwipeTracker()
        #expect(tracker.handle(phase: .changed, fingerDeltaX: -200, deltaY: 0) == nil)
    }

    @Test func `each gesture can trigger again`() {
        var tracker = SpaceSwipeTracker()
        #expect(tracker.handle(phase: .began, fingerDeltaX: -100, deltaY: 0) == .next)
        _ = tracker.handle(phase: .ended, fingerDeltaX: 0, deltaY: 0)
        #expect(tracker.handle(phase: .began, fingerDeltaX: 100, deltaY: 0) == .previous)
    }
}
