import AppKit
import SwiftUI

/// Donne accès à la `NSWindow` qui héberge la vue, pour régler ce que SwiftUI n'expose pas.
/// `configure` est appelé chaque fois que la vue rejoint une fenêtre.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context _: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.onWindowChange = configure
        return view
    }

    func updateNSView(_ view: WindowObservingView, context _: Context) {
        view.onWindowChange = configure
    }

    /// Vue invisible qui signale son arrivée dans une fenêtre.
    final class WindowObservingView: NSView {
        var onWindowChange: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindowChange?(window)
            }
        }
    }
}
