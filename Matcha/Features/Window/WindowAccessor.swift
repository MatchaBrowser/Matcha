import AppKit
import SwiftUI

/// Gives access to the `NSWindow` hosting the view, to adjust what SwiftUI does not expose.
/// `configure` is called each time the view joins a window.
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

    /// Invisible view that reports its arrival in a window.
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
