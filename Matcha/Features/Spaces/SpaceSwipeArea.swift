import AppKit
import SwiftUI

/// Zone de la barre latérale où un glissement horizontal à deux doigts change de Space.
/// Les défilements restent transmis à la barre (le défilement vertical continue de fonctionner).
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

    /// Lit les défilements qui passent au-dessus d'elle, même quand une vue de la barre les reçoit.
    final class SwipeView: NSView {
        var onSwipe: ((SpaceSwipeTracker.Direction) -> Void)?
        private var tracker = SpaceSwipeTracker()
        private var monitor: Any?

        /// Transparente aux clics : ils atteignent le fond (déplacement de la fenêtre) et les autres vues.
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
            // Sens des doigts, quel que soit le réglage du défilement naturel.
            let fingerDeltaX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            if let direction = tracker.handle(phase: phase, fingerDeltaX: fingerDeltaX, deltaY: event.scrollingDeltaY) {
                onSwipe?(direction)
            }
        }
    }
}
