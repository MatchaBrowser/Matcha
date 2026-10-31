import Foundation

/// Follows a two-finger swipe and decides when to switch Space: once per gesture, as soon as the
/// horizontal movement exceeds the threshold, unless the gesture is mostly vertical (scrolling).
nonisolated struct SpaceSwipeTracker: Sendable {
    /// Horizontal movement, in points, that triggers the switch.
    static let threshold = 80.0
    /// The gesture must be at least this many times more horizontal than vertical.
    static let horizontalDominance = 1.5

    enum Phase: Sendable {
        case began, changed, ended, cancelled
    }

    enum Direction: Equatable, Sendable {
        /// Fingers to the left: the next Space comes in from the right.
        case next
        case previous
    }

    private var horizontal = 0.0
    private var vertical = 0.0
    private var isTracking = false
    private var hasTriggered = false

    /// Handles a scroll event. `fingerDeltaX` follows the movement of the fingers (positive to the
    /// right), whatever the natural scrolling setting. Returns a direction at most once per gesture.
    mutating func handle(phase: Phase, fingerDeltaX: Double, deltaY: Double) -> Direction? {
        switch phase {
        case .began:
            (horizontal, vertical, isTracking, hasTriggered) = (fingerDeltaX, abs(deltaY), true, false)
        case .changed:
            guard isTracking else {
                return nil
            }
            horizontal += fingerDeltaX
            vertical += abs(deltaY)
        case .ended, .cancelled:
            isTracking = false
            return nil
        }
        guard !hasTriggered, abs(horizontal) >= Self.threshold, abs(horizontal) >= vertical * Self.horizontalDominance else {
            return nil
        }
        hasTriggered = true
        return horizontal < 0 ? .next : .previous
    }
}
