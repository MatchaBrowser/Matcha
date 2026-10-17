import AppKit
import SwiftUI
import WebKit

/// Posée derrière les panneaux d'un split : un clic (gauche, droit ou autre bouton) dans la page d'un
/// panneau appelle `onPageClick` avec son onglet, puis atteint la page (le clic n'est jamais retenu).
/// Barre de commande, barre flottante, séparateurs et barres d'adresse ne sont jamais pris pour une page.
struct PaneClickMonitor: NSViewRepresentable {
    /// Onglets affichés.
    let tabs: [BrowserTab]
    let onPageClick: (BrowserTab) -> Void

    func makeNSView(context _: Context) -> MonitorView {
        let view = MonitorView()
        view.tabs = tabs
        view.onPageClick = onPageClick
        return view
    }

    func updateNSView(_ view: MonitorView, context _: Context) {
        view.tabs = tabs
        view.onPageClick = onPageClick
    }

    /// Lit les clics de la fenêtre avant leur cible, sans en recevoir aucun.
    final class MonitorView: NSView {
        var tabs: [BrowserTab] = []
        var onPageClick: ((BrowserTab) -> Void)?
        private var monitor: Any?

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

        /// La vue qui recevra le clic est-elle (dans) la vue web d'un panneau affiché ?
        private func handle(_ event: NSEvent) {
            guard event.window === window, let contentView = window?.contentView else {
                return
            }
            let point = contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            guard let hit = contentView.hitTest(point),
                  let webView = sequence(first: hit, next: { $0.superview }).first(where: { $0 is WKWebView }),
                  let tab = tabs.first(where: { $0.webView === webView })
            else {
                return
            }
            onPageClick?(tab)
        }
    }
}
