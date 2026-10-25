import AppKit
import SwiftUI

/// A tab dragged out of the app's windows and dropped there opens in a window of its own, its top left corner under the
/// pointer, like “Open in New Window” (Arc's “This Window”). Needs the end of the drag session (macOS 26 and later):
/// before, only the menu does it. Never from a private window (its session is its own), nor the only tab of a window of
/// its own tabs (it already is alone).
struct TabDragOutModifier: ViewModifier {
    let tab: BrowserTab

    @Environment(WindowModel.self) private var windowModel: WindowModel?
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.onDragSessionUpdated { session in
                if case let .ended(operation) = session.phase, operation == .cancel {
                    openInNewWindowIfOutside()
                }
            }
        } else {
            content
        }
    }

    /// Nothing took the tab: if it was dropped outside the app's windows (desktop, another app), a new window opens
    /// where it was dropped.
    private func openInNewWindowIfOutside() {
        guard let windowModel, windowModel.canOpenInNewWindow else {
            return
        }
        let point = NSEvent.mouseLocation
        // The front window under the pointer, on this desktop, whichever app it belongs to (review ON21): one of
        // this app's windows took the drop, or refused it.
        let front = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard NSApp.window(withWindowNumber: front) == nil else {
            return
        }
        var state = windowModel.detachToNewWindow(tab)
        state.origin = Self.windowOrigin(forDropAt: point)
        openWindow(id: MatchaApp.browserWindowID, value: state)
    }

    /// Top left corner of the new window for a tab dropped at `point`: the pointer lands in its sidebar, under the band
    /// of the window buttons (`SidebarTopBar.height`), not on the green button (review ON21).
    nonisolated static func windowOrigin(forDropAt point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - 60, y: point.y + 48)
    }
}
