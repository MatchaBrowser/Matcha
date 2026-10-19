import AppKit

/// Window of a sign-in window (task 5.8): a real window with a title bar (the page's title), resizable, without a
/// minimize button (it stays attached to its originating window), never restored nor grouped into tabs.
final class PopupWindow: NSWindow {
    static let accessibilityID = "popupWindow"
    static let style: NSWindow.StyleMask = [.titled, .closable, .resizable]

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: Self.style, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isRestorable = false
        tabbingMode = .disallowed
        // Over a full-screen window; the green button zooms without going full screen.
        collectionBehavior = [.fullScreenAuxiliary]
        let minimum = PopupWindowPlacement.minimumPageSize
        contentMinSize = CGSize(width: minimum.width, height: minimum.height + PopupAddressBar.height)
        setAccessibilityIdentifier(Self.accessibilityID)
        setFrame(frame, display: false)
    }

    /// ⌘W closes the sign-in window, before the page and the menu: the “Close Tab” item must never target the tab
    /// of the browsing window behind it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCloseShortcut(event) {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌘W alone (without Shift: ⇧⌘W stays “Close Window”, which closes it too); Caps Lock does not count.
    static func isCloseShortcut(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "w"
    }
}
