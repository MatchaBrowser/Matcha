import AppKit
import SwiftUI

/// Placed behind the panel of the command bar or of the peek: a click in the same window outside the panel calls
/// `onOutsideClick`, then reaches its target (the click is never held back).
struct OutsideClickMonitor: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeNSView(context _: Context) -> MonitorView {
        let view = MonitorView()
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(_ view: MonitorView, context _: Context) {
        view.onOutsideClick = onOutsideClick
    }

    /// Reads the window's clicks before their target, without receiving any.
    final class MonitorView: NSView {
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        /// Transparent to clicks: only the panel, above, receives them.
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
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window, !bounds.contains(convert(event.locationInWindow, from: nil)) else {
                return
            }
            onOutsideClick?()
        }
    }
}
