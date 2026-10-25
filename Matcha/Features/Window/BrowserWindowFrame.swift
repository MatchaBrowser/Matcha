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

    /// Top left corner at `origin` (screen coordinates), the frame kept on the screen of `origin`, not on the one
    /// SwiftUI opened the window on (review ON17).
    static func place(_ window: NSWindow, topLeft origin: CGPoint) {
        var frame = window.frame
        frame.origin = CGPoint(x: origin.x, y: origin.y - frame.height)
        let screens = NSScreen.screens
        let screen = screenIndex(of: origin, in: screens.map(\.frame)).map { screens[$0] } ?? window.screen
        window.setFrame(window.constrainFrameRect(frame, to: screen), display: true)
    }

    /// Index of the screen frame that contains `point`, otherwise of the nearest one; nil without a screen.
    nonisolated static func screenIndex(of point: CGPoint, in frames: [CGRect]) -> Int? {
        if let index = frames.firstIndex(where: { $0.contains(point) }) {
            return index
        }
        func distance(_ frame: CGRect) -> Double {
            let horizontal = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let vertical = max(frame.minY - point.y, 0, point.y - frame.maxY)
            return horizontal * horizontal + vertical * vertical
        }
        return frames.indices.min { distance(frames[$0]) < distance(frames[$1]) }
    }

    /// Window of the browser window group (identifier given by SwiftUI: “browser-AppWindow-1”…).
    static func isBrowserWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(MatchaApp.browserWindowID + "-") == true
    }
}
