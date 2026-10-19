import AppKit

/// Window of a mini window: a floating panel (above Matcha's windows while the app is active, see
/// `MiniWindowLevels`), invisible title bar: the SwiftUI toolbar replaces it, with its own close button. Never
/// restored at the next launch.
final class MiniWindowPanel: NSPanel {
    static let accessibilityID = "miniWindow"

    /// ⎋ (or ⌘.) that neither the page nor the command bar kept. Otherwise an `NSPanel` closes on its own.
    var cancelHandler: (() -> Void)?

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        isFloatingPanel = true
        // A panel hides by default when the app goes to the background: the mini window stays
        // (it then goes back down to the normal level).
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isRestorable = false
        tabbingMode = .disallowed
        // Over a full-screen app; in Mission Control, ⌘` and the Window menu.
        collectionBehavior = [.fullScreenAuxiliary, .managed, .participatesInCycle]
        isExcludedFromWindowsMenu = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        contentMinSize = MiniWindowPlacement.minimumSize
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }
        setAccessibilityIdentifier(Self.accessibilityID)
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool {
        true
    }

    /// A panel does not become the main window by default: when the app is activated, macOS only brings the key and
    /// main windows to the front, and the browser window would then go over the app the shortcut came from.
    override var canBecomeMain: Bool {
        true
    }

    /// Without this override, ⎋ would close the panel (`NSPanel` behavior) and the page with it.
    override func cancelOperation(_: Any?) {
        cancelHandler?()
    }
}
