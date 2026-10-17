import AppKit
import SwiftUI

/// Posée derrière le panneau de la barre de commande ou de l'aperçu : un clic de la même fenêtre hors du
/// panneau appelle `onOutsideClick`, puis atteint sa cible (le clic n'est jamais retenu).
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

    /// Lit les clics de la fenêtre avant leur cible, sans en recevoir aucun.
    final class MonitorView: NSView {
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        /// Transparente aux clics : seul le panneau, au-dessus, les reçoit.
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
