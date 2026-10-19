import AppKit
import SwiftUI

/// Area of the sidebar where a horizontal two-finger swipe switches Space.
/// Scrolls are still passed on to the sidebar (vertical scrolling keeps working).
struct SpaceSwipeArea: NSViewRepresentable {
    let onSwipe: (SpaceSwipeTracker.Direction) -> Void

    func makeNSView(context _: Context) -> SwipeView {
        let view = SwipeView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: SwipeView, context _: Context) {
        view.onSwipe = onSwipe
    }

    /// Reads the scrolls that pass over it, even when a view of the sidebar receives them.
    final class SwipeView: NSView {
        var onSwipe: ((SpaceSwipeTracker.Direction) -> Void)?
        private var tracker = SpaceSwipeTracker()
        private var monitor: Any?

        /// Transparent to clicks: they reach the background (moving the window) and the other views.
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)), event.momentumPhase.isEmpty else {
                return
            }
            let phase: SpaceSwipeTracker.Phase
            switch event.phase {
            case .began: phase = .began
            case .changed: phase = .changed
            case .ended: phase = .ended
            case .cancelled: phase = .cancelled
            default: return
            }
            // Direction of the fingers, whatever the natural scrolling setting.
            let fingerDeltaX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            if let direction = tracker.handle(phase: phase, fingerDeltaX: fingerDeltaX, deltaY: event.scrollingDeltaY) {
                onSwipe?(direction)
            }
        }
    }
}
