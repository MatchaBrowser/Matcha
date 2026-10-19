import AppKit

/// Level of the mini windows: above Matcha's windows while the app is active; when another app comes to the front,
/// at the normal level, just above Matcha's frontmost window (they go behind the other app's windows, but not
/// behind the browser window). Never hidden.
@MainActor
enum MiniWindowLevels {
    static func raise(_ panels: [NSWindow]) {
        for panel in panels {
            panel.level = .floating
        }
    }

    /// From front to back, each one is placed just above the anchor: their order is preserved.
    static func lower(_ panels: [NSWindow]) {
        let windows = orderedFrontToBack()
        let ordered = windows.filter { window in panels.contains { $0 === window } }
        let anchor = windows.first { window in
            !panels.contains { $0 === window } && window.isVisible && window.level == .normal
        }
        for panel in ordered {
            panel.level = .normal
            if let anchor {
                panel.order(.above, relativeTo: anchor.windowNumber)
            }
        }
    }

    /// The app's windows, from front to back (panels included, unlike `NSApp.orderedWindows`).
    private static func orderedFrontToBack() -> [NSWindow] {
        (NSWindow.windowNumbers(options: []) ?? []).compactMap { NSApp.window(withWindowNumber: $0.intValue) }
    }
}
