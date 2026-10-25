import AppKit

/// AppKit settings of the window that SwiftUI does not expose.
@MainActor
enum WindowChrome {
    /// Transparent title bar. `isMovableByWindowBackground` stays disabled: it would turn any drag on a transparent
    /// area (handle, drag and drop) into a window move.
    static func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
    }

    /// Closes `window` like its red button, even when that button is hidden with the sidebar: `performClose` then
    /// only beeps (`DECISIONS.md`, 2026-10-17; review ON18).
    static func close(_ window: NSWindow?) {
        guard let window else {
            return
        }
        if window.standardWindowButton(.closeButton)?.isHidden == false {
            window.performClose(nil)
        } else {
            window.close()
        }
    }

    /// Hides or shows the red, yellow and green buttons.
    static func setButtonsHidden(_ hidden: Bool, in window: NSWindow?) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
        }
    }
}
