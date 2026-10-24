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
        guard let windowModel, !windowModel.session.isPrivate,
              windowModel.windowTabs == nil || windowModel.tabManager.tabs.count > 1
        else {
            return
        }
        let point = NSEvent.mouseLocation
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(point) }) else {
            return
        }
        var state = windowModel.detachToNewWindow(tab)
        // The pointer lands on the new window's sidebar, near its top.
        state.origin = CGPoint(x: point.x - 60, y: point.y + 16)
        openWindow(id: MatchaApp.browserWindowID, value: state)
    }
}
