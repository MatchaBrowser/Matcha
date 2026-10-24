import AppKit

/// Frame of the browser windows. SwiftUI saves none for windows opened with a value: the first browser window open keeps
/// its frame under “browser” (`NSWindow Frame browser`, like the single window of earlier versions), so its size and place
/// come back at the next launch. AppKit lets only one window use a name: the others open at the default size, or just
/// below and to the right of the front window when opened during use (⌘N, “Open in New Window”).
@MainActor
enum BrowserWindowFrame {
    static let autosaveName = "browser"
    /// Shift of a cascaded window, about the height of a title bar.
    static let cascadeOffset = 24.0

    /// Takes the saved frame and keeps it up to date, unless another browser window does.
    static func remember(_ window: NSWindow) {
        guard window.frameAutosaveName.isEmpty,
              !NSApp.windows.contains(where: { $0 !== window && $0.frameAutosaveName == autosaveName })
        else {
            return
        }
        window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
    }

    /// Just below and to the right of the front browser window, at its size; nothing without one.
    static func cascade(_ window: NSWindow) {
        guard let front = NSApp.orderedWindows.first(where: { $0 !== window && isBrowserWindow($0) }) else {
            return
        }
        var frame = front.frame
        frame.origin.x += cascadeOffset
        frame.origin.y -= cascadeOffset
        window.setFrame(window.constrainFrameRect(frame, to: front.screen), display: true)
    }

    /// Top left corner at `origin` (screen coordinates), the frame kept on its screen.
    static func place(_ window: NSWindow, topLeft origin: CGPoint) {
        var frame = window.frame
        frame.origin = CGPoint(x: origin.x, y: origin.y - frame.height)
        window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: true)
    }

    /// Window of the browser window group (identifier given by SwiftUI: “browser-AppWindow-1”…).
    static func isBrowserWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(MatchaApp.browserWindowID + "-") == true
    }
}
