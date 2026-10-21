import AppKit
import SwiftUI

/// Strip at the top of the window, where its title bar would be: dragging it moves the window, and a double click does
/// what System Settings > Desktop & Dock asks (zoom, unless the user chose to minimize), as on any title bar. The
/// window hides its title bar (`hiddenTitleBar`): the page and the sidebar cover it, so AppKit no longer does it.
struct TitleBarArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> AreaView {
        AreaView()
    }

    func updateNSView(_: AreaView, context _: Context) {}

    final class AreaView: NSView {
        /// Moves an inactive window at once, like its title bar.
        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else {
                return
            }
            if event.clickCount == 2 {
                TitleBarDoubleClick.current().perform(on: window)
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
