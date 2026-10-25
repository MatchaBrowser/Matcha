import AppKit

/// What the main window offers mini windows (a fake version in tests).
@MainActor
protocol MainWindowLink: AnyObject {
    /// Displayed Space; nil if the window has disappeared.
    var windowModel: WindowModel? { get }
    /// The window is on screen or in the Dock.
    var isShown: Bool { get }
    /// Closes its command bar, brings it to the front (taking it out of the Dock) and frees its keyboard.
    func bringToFront()
}

/// Real link, held by `MiniWindowManager`; it retains neither the window nor its state (`dismissCommandBar` holds the
/// command bar weakly, review IU3).
@MainActor
final class BrowserWindowLink: MainWindowLink {
    private(set) weak var windowModel: WindowModel?
    private weak var window: NSWindow?
    private let dismissCommandBar: @MainActor () -> Void

    init(windowModel: WindowModel, window: NSWindow?, dismissCommandBar: @escaping @MainActor () -> Void) {
        self.windowModel = windowModel
        self.window = window
        self.dismissCommandBar = dismissCommandBar
    }

    var isShown: Bool {
        guard let window else {
            return false
        }
        return window.isVisible || window.isMiniaturized
    }

    func bringToFront() {
        dismissCommandBar()
        guard let window else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
    }
}
