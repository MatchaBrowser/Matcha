import AppKit
import SwiftUI
import WebKit

/// Placed behind the panes of a split: a click (left, right or another button) in the page of a pane calls
/// `onPageClick` with its tab, then reaches the page (the click is never held back).
/// Command bar, floating sidebar, dividers and address bars are never taken for a page.
struct PaneClickMonitor: NSViewRepresentable {
    /// Displayed tabs.
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

    /// Reads the window's clicks before their target, without receiving any.
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

        /// Is the view that will receive the click (inside) the web view of a displayed pane?
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
